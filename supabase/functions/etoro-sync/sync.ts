// Una sincronización con eToro: tokens (con refresco), portfolio, historial,
// metadata de instrumentos, mapeo y escritura atómica. No sabe nada de HTTP.

import { EtoroClient, EtoroError, type EtoroTokens } from "./etoro.ts";
import { instrumentIds, type InstrumentMeta, mapPortfolio, pickLogo, possibleDuplicates } from "./mapping.ts";
import type { EtoroStore, SyncResult } from "./store.ts";

export const syncConfig = {
  /// Entre dos sincronizaciones del mismo usuario (abrir la app y
  /// pull-to-refresh piden; el servidor decide). Dentro de este rango se
  /// devuelve el último resultado guardado.
  minIntervalMs: 5 * 60 * 1000,
  /// El lease se libera al terminar; esto es solo si la función muere a mitad.
  lockSeconds: 120,
  /// Se refresca el access token si le queda menos que esto.
  refreshMarginMs: 60 * 1000,
  /// Primera importación del historial: hasta acá hacia atrás.
  firstImportHistoryDays: 5 * 365,
  /// La doc pide ventanas de menos de 1 año; si eToro rechaza la ventana
  /// larga, se reintenta con esta.
  fallbackHistoryDays: 364,
  /// Solapamiento de las sincronizaciones incrementales del historial (las
  /// repetidas no se duplican: unique por external_id).
  historyOverlapDays: 7,
};

export type SyncErrorType =
  | "etoro_not_connected"
  | "etoro_reconnect_required"
  | "etoro_sync_in_progress"
  | "etoro_rate_limited"
  | "etoro_unavailable"
  | "etoro_forbidden"
  | "etoro_sync_failed";

export type SyncOutcome =
  | { ok: true; result: SyncResult; throttled: boolean }
  | { ok: false; error: SyncErrorType; retryAfterSeconds?: number };

export type SyncContext = {
  userId: string;
  store: EtoroStore;
  client: EtoroClient;
  now: () => number;
  /// Al conectar: ignora el intervalo mínimo.
  force?: boolean;
};

/// UUID estable a partir de (usuario, tipo, id de eToro): la misma posición
/// conserva su id en Porty entre sincronizaciones (el detalle navega por id).
export async function stableUuid(userId: string, kind: string, externalId: string): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${userId}:etoro:${kind}:${externalId}`)),
  );
  const b = digest.slice(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50; // versión 5 (basado en nombre)
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  const hex = [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function isoDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

const dayMs = 24 * 60 * 60 * 1000;

export async function runSync(ctx: SyncContext): Promise<SyncOutcome> {
  const { userId, store, client, now } = ctx;

  const connection = await store.getConnection(userId);
  if (!connection || connection.status === "disconnected") return { ok: false, error: "etoro_not_connected" };
  if (connection.status === "reconnect_required") return { ok: false, error: "etoro_reconnect_required" };

  if (
    !ctx.force && connection.lastResult && connection.lastSyncAt &&
    now() - Date.parse(connection.lastSyncAt) < syncConfig.minIntervalMs
  ) {
    return { ok: true, result: connection.lastResult, throttled: true };
  }

  if (!(await store.tryLock(userId, syncConfig.lockSeconds))) {
    return { ok: false, error: "etoro_sync_in_progress" };
  }

  try {
    let tokens = await store.readTokens(userId);
    if (!tokens) {
      await store.markReconnectRequired(userId);
      return { ok: false, error: "etoro_reconnect_required" };
    }

    let refreshed = false;
    const refresh = async (current: EtoroTokens): Promise<EtoroTokens> => {
      if (!current.refreshToken) throw new EtoroError("invalid_grant", "no refresh token");
      const next = await client.refresh(current.refreshToken);
      // El refresh token rota: se guarda ANTES de usar el access token nuevo.
      await store.saveTokens(userId, next);
      refreshed = true;
      return next;
    };

    if (tokens.expiresAt - now() < syncConfig.refreshMarginMs) tokens = await refresh(tokens);

    // Un 401 con un token que no acabamos de refrescar: un refresco y un
    // reintento. Si vuelve a fallar, la sesión está muerta.
    const call = async <T>(fn: (accessToken: string) => Promise<T>): Promise<T> => {
      try {
        return await fn(tokens!.accessToken);
      } catch (e) {
        if (e instanceof EtoroError && e.type === "unauthorized" && !refreshed) {
          tokens = await refresh(tokens!);
          return await fn(tokens.accessToken);
        }
        if (e instanceof EtoroError && e.type === "unauthorized") {
          throw new EtoroError("invalid_grant", "401 after refresh");
        }
        throw e;
      }
    };

    const { positions, creditUsd } = await call((t) => client.portfolio(t));

    const today = now();
    const firstImport = !connection.historySyncedUntil;
    const minDate = firstImport
      ? isoDate(today - syncConfig.firstImportHistoryDays * dayMs)
      : isoDate(Date.parse(connection.historySyncedUntil!) - syncConfig.historyOverlapDays * dayMs);
    let history: Record<string, unknown>[];
    try {
      history = await call((t) => client.history(t, minDate));
    } catch (e) {
      // Ventana demasiado larga para eToro: el último año.
      if (e instanceof EtoroError && e.type === "bad_response" && e.status === 400) {
        history = await call((t) => client.history(t, isoDate(today - syncConfig.fallbackHistoryDays * dayMs)));
      } else {
        throw e;
      }
    }

    const ids = instrumentIds(positions, history);
    const instruments = await store.getInstruments(ids);
    const missing = ids.filter((id) => !instruments.has(id));
    if (missing.length > 0) {
      // En serie: en paralelo, tres 401 harían tres refrescos que se pisan
      // (el refresh token rota).
      const raw = await call((t) => client.instruments(t, missing));
      const types = await call((t) => client.instrumentTypes(t));
      const exchanges = await call((t) => client.exchanges(t));
      const fresh: InstrumentMeta[] = [];
      for (const r of raw) {
        const id = Number(r.instrumentID ?? r.instrumentId);
        const symbol = r.symbolFull;
        if (!Number.isFinite(id) || typeof symbol !== "string") continue;
        const meta: InstrumentMeta = {
          instrumentId: id,
          symbolFull: symbol,
          displayName: typeof r.instrumentDisplayName === "string" ? r.instrumentDisplayName : null,
          instrumentType: types.get(Number(r.instrumentTypeID)) ?? null,
          exchange: exchanges.get(Number(r.exchangeID)) ?? null,
          logoUrl: pickLogo(r.images),
        };
        instruments.set(id, meta);
        fresh.push(meta);
      }
      await store.saveInstruments(fresh);
    }

    const mapped = mapPortfolio(positions, history, instruments);
    const manual = await store.manualOpenTickers(userId);
    const result: SyncResult = {
      imported: mapped.open.length,
      closedImported: mapped.closed.length,
      notImported: mapped.notImported,
      closedNotImported: mapped.closedNotImported,
      possibleDuplicates: possibleDuplicates(manual, mapped.open),
      syncedAt: new Date(today).toISOString(),
      cashUsd: creditUsd === null ? null : Math.round(creditUsd * 100) / 100,
      otherHoldings: mapped.otherHoldings,
      logos: mapped.logos,
    };

    await store.applySync(userId, {
      open: await Promise.all(
        mapped.open.map(async (r) => ({ ...r, id: await stableUuid(userId, "open", r.externalId) })),
      ),
      closed: await Promise.all(
        mapped.closed.map(async (r) => ({ ...r, id: await stableUuid(userId, "closed", r.externalId) })),
      ),
      result,
      historyUntil: isoDate(today),
    });

    return { ok: true, result, throttled: false };
  } catch (e) {
    if (e instanceof EtoroError) {
      switch (e.type) {
        case "invalid_grant":
          await store.markReconnectRequired(userId);
          return { ok: false, error: "etoro_reconnect_required" };
        case "rate_limited":
          await store.markSyncError(userId, "etoro_rate_limited");
          return { ok: false, error: "etoro_rate_limited", retryAfterSeconds: e.retryAfterSeconds ?? 60 };
        case "unavailable":
          await store.markSyncError(userId, "etoro_unavailable");
          return { ok: false, error: "etoro_unavailable" };
        case "forbidden":
          await store.markSyncError(userId, "etoro_forbidden");
          return { ok: false, error: "etoro_forbidden" };
        default:
          await store.markSyncError(userId, "etoro_sync_failed");
          console.error(JSON.stringify({ fn: "etoro-sync", op: "sync", etoroError: e.type, status: e.status }));
          return { ok: false, error: "etoro_sync_failed" };
      }
    }
    await store.markSyncError(userId, "etoro_sync_failed").catch(() => {});
    console.error(JSON.stringify({ fn: "etoro-sync", op: "sync", error: (e as Error).message }));
    return { ok: false, error: "etoro_sync_failed" };
  } finally {
    await store.unlock(userId).catch(() => {});
  }
}

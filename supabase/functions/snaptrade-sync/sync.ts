// Una sincronización: posiciones de los brókers conectados en SnapTrade →
// posiciones `snaptrade` de Porty.

import { type BrokerageSummary, type Holding, mapPositions, selectBrokerages } from "./mapping.ts";
import { type SnaptradeClient, SnaptradeError } from "./snaptrade.ts";
import type { PositionRow, SnaptradeStore } from "./store.ts";

export const syncConfig = {
  /// Si hubo una hace menos, devuelve esa (salvo al volver del portal).
  minIntervalMs: 5 * 60 * 1000,
  lockSeconds: 90,
  /// Tope de cuentas que se leen en una sincronización (una consulta cada
  /// una).
  maxAccounts: 20,
};

export type SyncErrorType =
  | "snaptrade_not_connected"
  | "snaptrade_reconnect_required"
  | "snaptrade_sync_in_progress"
  | "snaptrade_rate_limited"
  | "snaptrade_unavailable";

export type SyncResult = {
  imported: number;
  notImported: { ticker: string; broker: string; reason: string }[];
  /// Tickers sin precio de compra del bróker: precio de compra = el de hoy.
  estimatedCost: string[];
  syncedAt: string;
};

export type SyncOutcome =
  | { ok: true; result: SyncResult; throttled: boolean }
  | { ok: false; error: SyncErrorType };

export async function runSync(opts: {
  userId: string;
  store: SnaptradeStore;
  client: SnaptradeClient;
  now: () => number;
  maxBrokerages: number | null;
  force?: boolean;
  newId?: () => string;
}): Promise<SyncOutcome> {
  const { userId, store, client, now } = opts;
  const connection = await store.getConnection(userId);
  if (!connection || connection.status === "disconnected") return { ok: false, error: "snaptrade_not_connected" };
  if (connection.status === "reconnect_required") return { ok: false, error: "snaptrade_reconnect_required" };
  if (
    !opts.force && connection.lastSyncAt && connection.lastResult &&
    now() - Date.parse(connection.lastSyncAt) < syncConfig.minIntervalMs
  ) {
    return { ok: true, result: connection.lastResult as SyncResult, throttled: true };
  }

  if (!(await store.tryLock(userId, syncConfig.lockSeconds))) return { ok: false, error: "snaptrade_sync_in_progress" };
  try {
    const user = await store.readUser(userId);
    if (!user) {
      await store.markError(userId, "snaptrade_reconnect_required", true);
      return { ok: false, error: "snaptrade_reconnect_required" };
    }
    const brokerages = selectBrokerages(await client.authorizations(user), opts.maxBrokerages);
    const { positions, result } = await snapshot(client, user, brokerages, now, opts.newId);
    await store.applySync(userId, positions, brokerages, result);
    return { ok: true, result, throttled: false };
  } catch (e) {
    const type: SyncErrorType = !(e instanceof SnaptradeError)
      ? "snaptrade_unavailable"
      : e.type === "auth" || e.type === "not_found"
      ? "snaptrade_reconnect_required"
      : e.type === "rate_limited"
      ? "snaptrade_rate_limited"
      : "snaptrade_unavailable";
    if (!(e instanceof SnaptradeError)) console.error("snaptrade-sync failed", String(e));
    await store.markError(userId, type, type === "snaptrade_reconnect_required").catch(() => {});
    return { ok: false, error: type };
  } finally {
    await store.unlock(userId).catch(() => {});
  }
}

/// La foto de las cuentas de los brókers que se importan.
export async function snapshot(
  client: SnaptradeClient,
  user: { userId: string; userSecret: string },
  brokerages: BrokerageSummary[],
  now: () => number,
  newId: () => string = () => crypto.randomUUID(),
): Promise<{ positions: PositionRow[]; result: SyncResult }> {
  const imported = new Map(brokerages.filter((b) => b.imported).map((b) => [b.id, b.name]));
  const nowIso = new Date(now()).toISOString();
  const byExternal = new Map<string, Holding>();
  const notImported: SyncResult["notImported"] = [];

  if (imported.size > 0) {
    const accounts = (await client.accounts(user))
      .filter((a) => imported.has(a.authorizationId))
      .slice(0, syncConfig.maxAccounts);
    for (const account of accounts) {
      const broker = imported.get(account.authorizationId) || account.institution;
      let raw;
      try {
        raw = await client.positions(user, account.id);
      } catch (e) {
        // Una cuenta que se cerró entre una consulta y otra no corta todo.
        if (e instanceof SnaptradeError && e.type === "not_found") continue;
        throw e;
      }
      const { holdings, skipped } = mapPositions(raw);
      for (const s of skipped) notImported.push({ ...s, broker });
      for (const h of holdings) {
        // El mismo ticker dos veces en una cuenta (lotes): se suman, con el
        // costo promedio ponderado.
        const key = `${account.id}:${h.ticker}`;
        const prev = byExternal.get(key);
        byExternal.set(key, prev ? merge(prev, h) : h);
      }
    }
  }

  const positions: PositionRow[] = [];
  const estimated = new Set<string>();
  for (const [externalId, h] of byExternal) {
    if (h.cost === null) estimated.add(h.ticker);
    positions.push({
      id: newId(),
      external_id: externalId,
      ticker: h.ticker,
      quantity: round(h.quantity, 8),
      purchase_price: round(h.cost ?? h.price, 8),
      purchase_date: nowIso,
      broker_price: round(h.price, 8),
    });
  }
  return {
    positions,
    result: {
      imported: positions.length,
      notImported,
      estimatedCost: [...estimated].sort(),
      syncedAt: nowIso,
    },
  };
}

function merge(a: Holding, b: Holding): Holding {
  const quantity = a.quantity + b.quantity;
  const cost = a.cost !== null && b.cost !== null ? (a.cost * a.quantity + b.cost * b.quantity) / quantity : null;
  return { ticker: a.ticker, quantity, cost, price: b.price };
}

function round(v: number, decimals: number): number {
  const f = 10 ** decimals;
  return Math.round(v * f) / f;
}

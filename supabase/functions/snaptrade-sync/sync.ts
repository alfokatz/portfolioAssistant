// Una sincronización: posiciones de los brókers conectados en SnapTrade →
// posiciones `snaptrade` de Porty.

import { lotsFor, type Trade } from "./lots.ts";
import { activityTicker, type BrokerageSummary, type Holding, mapPositions, selectBrokerages } from "./mapping.ts";
import { type SnaptradeClient, SnaptradeError } from "./snaptrade.ts";
import type { ClosedRow, PositionRow, SnaptradeStore } from "./store.ts";

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
    const [auths, direct] = await Promise.all([client.authorizations(user), store.directConnections(userId)]);
    const selected = selectBrokerages(auths, opts.maxBrokerages, direct);
    // Lo que ya está conectado directo en Porty (gratis) se quita de
    // SnapTrade: no se duplica ni se paga. Si no queda nada, se borra el
    // usuario de SnapTrade, que es lo que deja de cobrarse.
    const duplicated = selected.filter((b) => b.reason === "direct_connection");
    for (const b of duplicated) await client.deleteAuthorization(user, b.id);
    const brokerages = selected.filter((b) => b.reason !== "direct_connection");
    if (duplicated.length > 0 && brokerages.length === 0) {
      await client.deleteUser(user.userId);
      await store.disconnect(userId, false);
      const syncedAt = new Date(now()).toISOString();
      return { ok: true, result: { imported: 0, notImported: [], estimatedCost: [], syncedAt }, throttled: false };
    }
    const { positions, closed, result } = await snapshot(client, user, brokerages, now, opts.newId);
    await store.applySync(userId, positions, closed, brokerages, result);
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

/// La foto de las cuentas de los brókers que se importan: cada compra que
/// sigue abierta es una fila (con su fecha y su precio, del historial de
/// operaciones) y cada venta, una cerrada. Si SnapTrade no da el historial,
/// una fila por ticker con el costo promedio del bróker, como antes.
export async function snapshot(
  client: SnaptradeClient,
  user: { userId: string; userSecret: string },
  brokerages: BrokerageSummary[],
  now: () => number,
  newId: () => string = () => crypto.randomUUID(),
): Promise<{ positions: PositionRow[]; closed: ClosedRow[]; result: SyncResult }> {
  const imported = new Map(brokerages.filter((b) => b.imported).map((b) => [b.id, b.name]));
  const nowIso = new Date(now()).toISOString();
  const positions: PositionRow[] = [];
  const closed: ClosedRow[] = [];
  const tickers = new Set<string>();
  const estimated = new Set<string>();
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
      // El mismo ticker dos veces en una cuenta: se suman, con el costo
      // promedio ponderado.
      const held = new Map<string, Holding>();
      for (const h of holdings) {
        const prev = held.get(h.ticker);
        held.set(h.ticker, prev ? merge(prev, h) : h);
      }

      const trades = await tradesOf(client, user, account.id);
      const byTicker = new Map<string, Trade[]>();
      for (const t of trades) byTicker.set(t.ticker, [...(byTicker.get(t.ticker) ?? []), t]);

      for (const [ticker, h] of held) {
        tickers.add(ticker);
        if (h.cost === null) estimated.add(ticker);
        const { lots } = lotsFor(byTicker.get(ticker) ?? [], h.quantity, h.cost, h.price, nowIso);
        for (const lot of lots) {
          positions.push({
            id: newId(),
            external_id: `${account.id}:${ticker}:${lot.id}`,
            ticker,
            quantity: round(lot.units, 8),
            purchase_price: round(lot.price, 8),
            purchase_date: new Date(lot.date).toISOString(),
            broker_price: round(h.price, 8),
          });
        }
      }
      // Las ventas, también de lo que ya no tiene.
      for (const [ticker, list] of byTicker) {
        const h = held.get(ticker);
        const { closed: sales } = lotsFor(list, h?.quantity ?? 0, h?.cost ?? null, h?.price ?? 0, nowIso);
        for (const c of sales) {
          closed.push({
            id: newId(),
            external_id: `${account.id}:${c.id}`,
            ticker,
            quantity: round(c.units, 8),
            avg_purchase_price: round(c.avgPurchasePrice, 8),
            close_price: round(c.closePrice, 8),
            close_date: new Date(c.closeDate).toISOString(),
            realized_pnl: round(c.realizedPnl, 2),
          });
        }
      }
    }
  }

  return {
    positions,
    closed,
    result: {
      imported: tickers.size,
      notImported,
      estimatedCost: [...estimated].sort(),
      syncedAt: nowIso,
    },
  };
}

/// Las compras y ventas de la cuenta con el ticker de Porty. Si SnapTrade
/// no las da (cuenta sin historial, error), sin historial: no corta la
/// sincronización.
async function tradesOf(
  client: SnaptradeClient,
  user: { userId: string; userSecret: string },
  accountId: string,
): Promise<Trade[]> {
  let raw;
  try {
    raw = await client.activities(user, accountId);
  } catch (e) {
    if (e instanceof SnaptradeError && (e.type === "not_found" || e.type === "unavailable")) {
      log({ op: "activities", outcome: e.type });
      return [];
    }
    throw e;
  }
  const trades = raw.flatMap((a) => {
    const ticker = activityTicker(a.symbol, a.securityType);
    return ticker && !Number.isNaN(Date.parse(a.tradeDate))
      ? [{ id: a.id, type: a.type, ticker, units: a.units, price: a.price, fee: a.fee, date: a.tradeDate }]
      : [];
  });
  // Cuántas operaciones da el bróker (sin ids): si da 0, las compras quedan
  // sin fecha (algunos brókers no las informan por SnapTrade).
  log({ op: "activities", raw: raw.length, trades: trades.length });
  return trades;
}

function log(fields: Record<string, unknown>) {
  console.log(JSON.stringify({ fn: "snaptrade-sync", ...fields }));
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

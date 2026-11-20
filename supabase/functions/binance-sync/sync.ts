// Una sincronización: saldos de Binance → posiciones `binance` de Porty.

import { type BinanceClient, BinanceError, type BinanceKeys } from "./binance.ts";
import { averageCost, mapBalances, portyTicker } from "./mapping.ts";
import type { BinanceStore, PositionRow } from "./store.ts";

export const syncConfig = {
  /// Si hubo una hace menos, devuelve esa (salvo al conectar).
  minIntervalMs: 5 * 60 * 1000,
  lockSeconds: 90,
  /// Para cuántos activos (los de más valor) se buscan las operaciones para
  /// el precio de compra. Cada consulta pesa 20 en el límite de Binance.
  maxTradeLookups: 15,
};

export type SyncErrorType =
  | "binance_not_connected"
  | "binance_reconnect_required"
  | "binance_sync_in_progress"
  | "binance_rate_limited"
  | "binance_region_blocked"
  | "binance_unavailable";

export type SyncResult = {
  imported: number;
  notImported: { asset: string; reason: string }[];
  /// Tickers sin historial suficiente: precio de compra = el de hoy.
  estimatedCost: string[];
  syncedAt: string;
};

export type SyncOutcome =
  | { ok: true; result: SyncResult; throttled: boolean }
  | { ok: false; error: SyncErrorType };

export async function runSync(opts: {
  userId: string;
  store: BinanceStore;
  client: BinanceClient;
  now: () => number;
  force?: boolean;
  newId?: () => string;
}): Promise<SyncOutcome> {
  const { userId, store, client, now } = opts;
  const connection = await store.getConnection(userId);
  if (!connection || connection.status === "disconnected") return { ok: false, error: "binance_not_connected" };
  if (connection.status === "reconnect_required") return { ok: false, error: "binance_reconnect_required" };
  if (
    !opts.force && connection.lastSyncAt && connection.lastResult &&
    now() - Date.parse(connection.lastSyncAt) < syncConfig.minIntervalMs
  ) {
    return { ok: true, result: connection.lastResult as SyncResult, throttled: true };
  }

  if (!(await store.tryLock(userId, syncConfig.lockSeconds))) return { ok: false, error: "binance_sync_in_progress" };
  try {
    const keys = await store.readKeys(userId);
    if (!keys) {
      await store.markError(userId, "binance_reconnect_required", true);
      return { ok: false, error: "binance_reconnect_required" };
    }
    const { positions, result } = await snapshot(client, keys, now, opts.newId);
    await store.applySync(userId, positions, result);
    return { ok: true, result, throttled: false };
  } catch (e) {
    const type: SyncErrorType = !(e instanceof BinanceError)
      ? "binance_unavailable"
      : e.type === "invalid_key"
      ? "binance_reconnect_required"
      : e.type === "rate_limited"
      ? "binance_rate_limited"
      : e.type === "region_blocked"
      ? "binance_region_blocked"
      : "binance_unavailable";
    if (!(e instanceof BinanceError)) console.error("binance-sync failed", String(e));
    await store.markError(userId, type, type === "binance_reconnect_required").catch(() => {});
    return { ok: false, error: type };
  } finally {
    await store.unlock(userId).catch(() => {});
  }
}

/// La foto de la cuenta: posiciones para `binance_apply_sync` y el resumen
/// para la app.
export async function snapshot(
  client: BinanceClient,
  keys: BinanceKeys,
  now: () => number,
  newId: () => string = () => crypto.randomUUID(),
): Promise<{ positions: PositionRow[]; result: SyncResult }> {
  const [balances, prices] = await Promise.all([client.balances(keys), client.prices()]);
  const { holdings, notImported } = mapBalances(balances, prices);
  const nowIso = new Date(now()).toISOString();
  const positions: PositionRow[] = [];
  const estimated: string[] = [];
  for (const [i, h] of holdings.entries()) {
    let cost: { price: number; openedAt: number } | null = null;
    if (i < syncConfig.maxTradeLookups) {
      const trades = [];
      for (const quote of ["USDT", "USDC"]) {
        if (!prices.has(`${h.asset}${quote}`)) continue;
        trades.push(...await client.trades(`${h.asset}${quote}`, keys));
      }
      cost = averageCost(h.asset, trades, h.quantity);
    }
    const ticker = portyTicker(h.asset);
    if (!cost) estimated.push(ticker);
    positions.push({
      id: newId(),
      external_id: h.asset,
      ticker,
      quantity: round(h.quantity, 8),
      purchase_price: round(cost?.price ?? h.price, 8),
      purchase_date: cost?.openedAt ? new Date(cost.openedAt).toISOString() : nowIso,
      broker_price: round(h.price, 8),
    });
  }
  return {
    positions,
    result: { imported: positions.length, notImported, estimatedCost: estimated, syncedAt: nowIso },
  };
}

function round(v: number, decimals: number): number {
  const f = 10 ** decimals;
  return Math.round(v * f) / f;
}

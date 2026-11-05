// Binance → Porty, puro: permisos de la clave, saldos a posiciones y
// precio de compra promedio a partir de las operaciones.

import type { ApiRestrictions, Balance, Trade } from "./binance.ts";

/// Permisos que una clave de Porty NO puede tener (cualquiera que opere,
/// retire o mueva fondos).
export const forbiddenPermissions = [
  "enableWithdrawals",
  "enableInternalTransfer",
  "permitsUniversalTransfer",
  "enableSpotAndMarginTrading",
  "enableMargin",
  "enableFutures",
  "enableVanillaOptions",
  "enablePortfolioMarginTrading",
  "enableFixApiTrade",
];

/// `null` si la clave sirve (solo lectura); si no, por qué no.
export function keyProblem(r: ApiRestrictions): "write_permissions" | "no_read" | null {
  if (forbiddenPermissions.some((p) => r[p] === true)) return "write_permissions";
  if (r.enableReading !== true) return "no_read";
  return null;
}

/// Dólares digitales y monedas: no son una inversión que Porty muestre
/// (como el efectivo de eToro).
export const cashAssets = new Set([
  "USDT",
  "USDC",
  "FDUSD",
  "BUSD",
  "TUSD",
  "DAI",
  "USDP",
  "PYUSD",
  "USDE",
  "USD1",
  "EUR",
  "GBP",
  "TRY",
  "BRL",
  "ARS",
  "MXN",
  "COP",
  "AUD",
  "UAH",
  "RUB",
  "JPY",
  "PLN",
  "ZAR",
  "RON",
  "CZK",
]);

/// Por debajo de esto (en USD) es polvo de operaciones viejas.
export const dustUsd = 1;

export type NotImportedReason = "cash" | "dust" | "no_price";

export type Holding = { asset: string; quantity: number; price: number; value: number };

/// Precio en USD de [asset] con los pares de Binance: contra USDT, USDC o
/// FDUSD; si no, contra BTC.
export function usdPrice(asset: string, prices: Map<string, number>): number | null {
  for (const quote of ["USDT", "USDC", "FDUSD"]) {
    const p = prices.get(`${asset}${quote}`);
    if (p && p > 0) return p;
  }
  const inBtc = prices.get(`${asset}BTC`);
  const btc = prices.get("BTCUSDT");
  return inBtc && btc ? inBtc * btc : null;
}

/// Saldos (libre + bloqueado) a tenencias valuadas. Lo de Simple Earn
/// flexible viene como "LD" + activo (`LDBTC`) y suma al activo, salvo que
/// el nombre sea un activo propio con precio (`LDO`).
export function mapBalances(
  balances: Balance[],
  prices: Map<string, number>,
): { holdings: Holding[]; notImported: { asset: string; reason: NotImportedReason }[] } {
  const quantities = new Map<string, number>();
  for (const b of balances) {
    let asset = b.asset.toUpperCase();
    if (asset.startsWith("LD") && asset.length > 2 && usdPrice(asset, prices) === null) {
      const base = asset.slice(2);
      if (cashAssets.has(base) || usdPrice(base, prices) !== null) asset = base;
    }
    quantities.set(asset, (quantities.get(asset) ?? 0) + b.free + b.locked);
  }
  const holdings: Holding[] = [];
  const notImported: { asset: string; reason: NotImportedReason }[] = [];
  for (const [asset, quantity] of quantities) {
    if (!(quantity > 0)) continue;
    if (cashAssets.has(asset)) {
      notImported.push({ asset, reason: "cash" });
      continue;
    }
    const price = usdPrice(asset, prices);
    if (price === null) {
      notImported.push({ asset, reason: "no_price" });
      continue;
    }
    const value = quantity * price;
    if (value < dustUsd) {
      notImported.push({ asset, reason: "dust" });
      continue;
    }
    holdings.push({ asset, quantity, price, value });
  }
  holdings.sort((a, b) => b.value - a.value);
  notImported.sort((a, b) => a.asset.localeCompare(b.asset));
  return { holdings, notImported };
}

/// Precio promedio de compra de lo que tiene hoy, a partir de sus
/// operaciones (costo promedio: las ventas sacan al promedio). `null` si
/// las operaciones no explican al menos la mitad de lo que tiene (lo
/// compró en otro par o lo transfirió): ahí Porty no inventa un costo.
export function averageCost(
  asset: string,
  trades: Trade[],
  heldQuantity: number,
): { price: number; openedAt: number } | null {
  let qty = 0;
  let cost = 0;
  let openedAt = 0;
  for (const t of [...trades].sort((a, b) => a.time - b.time)) {
    if (!(t.qty > 0) || !(t.price > 0)) continue;
    if (t.isBuyer) {
      if (qty <= 1e-12) openedAt = t.time;
      const fee = t.commissionAsset.toUpperCase() === asset ? t.commission : 0;
      cost += t.qty * t.price;
      qty += t.qty - fee;
    } else if (qty > 0) {
      const sold = Math.min(t.qty, qty);
      cost -= (cost / qty) * sold;
      qty -= sold;
      if (qty <= 1e-12) {
        qty = 0;
        cost = 0;
      }
    }
  }
  if (!(qty > 0) || qty < heldQuantity * 0.5) return null;
  return { price: cost / qty, openedAt };
}

/// Ticker de Yahoo para un activo de Binance.
export function portyTicker(asset: string): string {
  return `${asset.toUpperCase()}-USD`;
}

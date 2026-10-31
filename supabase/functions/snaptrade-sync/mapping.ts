// De lo que devuelve SnapTrade a lo que guarda Porty: qué brókers se
// importan según el plan, y qué posiciones entran.

import type { Authorization, RawPosition } from "./snaptrade.ts";

/// Qué incluye cada plan pago. Free no conecta (el handler lo corta antes).
/// - Premium: un bróker, datos del día.
/// - Gold: todos los brókers y "Actualizar ahora" (si está habilitado:
///   SnapTrade cobra cada actualización manual).
export const planConfig: Record<string, { maxBrokerages: number | null; manualRefresh: boolean }> = {
  premium: { maxBrokerages: 1, manualRefresh: false },
  gold: { maxBrokerages: null, manualRefresh: true },
};

/// Brókers que Porty conecta directo (sin costo por usuario): por SnapTrade
/// no se importan, para no duplicar ni pagar dos veces.
const directBrokers = /etoro|binance/i;

export type BrokerageSummary = {
  id: string;
  name: string;
  slug: string;
  disabled: boolean;
  /// false: conectado en SnapTrade pero Porty no lo importa.
  imported: boolean;
  /// Por qué no se importa: `plan_limit`, `direct_connection` o
  /// `trade_permissions`.
  reason?: string;
};

/// Qué conexiones se importan. Las de solo lectura, sin los brókers que
/// Porty conecta directo y, si el plan tiene tope, las más viejas.
export function selectBrokerages(auths: Authorization[], maxBrokerages: number | null): BrokerageSummary[] {
  const sorted = [...auths].sort((a, b) => a.createdAt.localeCompare(b.createdAt) || a.id.localeCompare(b.id));
  let used = 0;
  return sorted.map((a) => {
    const base = { id: a.id, name: a.name, slug: a.slug, disabled: a.disabled };
    // Porty solo pide `read`; si apareciera una con permiso de operar, no
    // se usa.
    if (a.type !== "read") return { ...base, imported: false, reason: "trade_permissions" };
    if (directBrokers.test(a.slug) || directBrokers.test(a.name)) {
      return { ...base, imported: false, reason: "direct_connection" };
    }
    if (maxBrokerages !== null && used >= maxBrokerages) return { ...base, imported: false, reason: "plan_limit" };
    used++;
    return { ...base, imported: true };
  });
}

/// Cuántas conexiones cuentan para el tope del plan (las que se importan o
/// se importarían).
export function countedBrokerages(auths: Authorization[]): number {
  return selectBrokerages(auths, null).filter((b) => b.imported).length;
}

const importableKinds = new Set(["stock", "adr", "etf", "cef", "mutualfund", "crypto"]);

export type Holding = {
  ticker: string;
  quantity: number;
  /// Precio de compra por unidad; null si el bróker no lo informó.
  cost: number | null;
  price: number;
};

export type Skipped = { ticker: string; reason: string };

/// El ticker como lo usa Porty (formato de Yahoo, igual que SnapTrade). Las
/// criptos van contra el dólar: `BTC` → `BTC-USD`.
export function portyTicker(p: RawPosition): string {
  const symbol = (p.symbol || p.rawSymbol).trim().toUpperCase();
  if (p.kind === "crypto" && !symbol.includes("-")) return `${symbol}-USD`;
  return symbol;
}

/// Posiciones de una cuenta → lo que se importa y lo que no (con el motivo).
/// - `cash`: efectivo o fondos que cuentan como efectivo.
/// - `unsupported`: opciones, futuros, CFD, bonos y otros.
/// - `short`: posiciones vendidas en corto.
/// - `no_price`: sin precio ni costo para valuarla.
export function mapPositions(positions: RawPosition[]): { holdings: Holding[]; skipped: Skipped[] } {
  const holdings: Holding[] = [];
  const skipped: Skipped[] = [];
  for (const p of positions) {
    if (p.units === 0) continue;
    const ticker = portyTicker(p);
    if (p.kind === "cash" || p.cashEquivalent) {
      skipped.push({ ticker: ticker || (p.currency ?? "CASH"), reason: "cash" });
      continue;
    }
    if (!importableKinds.has(p.kind) || !ticker) {
      skipped.push({ ticker: ticker || p.kind, reason: "unsupported" });
      continue;
    }
    if (p.units < 0) {
      skipped.push({ ticker, reason: "short" });
      continue;
    }
    const cost = p.costBasis !== null && p.costBasis > 0 ? p.costBasis : null;
    const price = p.price !== null && p.price > 0 ? p.price : cost;
    if (price === null) {
      skipped.push({ ticker, reason: "no_price" });
      continue;
    }
    holdings.push({ ticker, quantity: p.units, cost, price });
  }
  return { holdings, skipped };
}

// Movimientos fuertes (F4 del plan, §4.3). Puro: de las posiciones de cada
// usuario y las cotizaciones salen los candidatos; agrupar, no repetir y
// combinar con el de la cartera lo hace `market_enqueue_moves`.

import type { Quote } from "./quotes.ts";

export type Sensitivity = "low" | "normal" | "high";

export type Holding = {
  user_id: string;
  symbol: string;
  quantity: number;
  sensitivity: Sensitivity;
  big_moves: boolean;
  portfolio_moves: boolean;
};

export type MoveCandidate = {
  symbol: string;
  change_pct: number;
  weight_pct: number;
  direction: "up" | "down";
  /// 1: pasó el umbral. 2: pasó el doble (puede avisar una vez más).
  level: 1 | 2;
};

export type PortfolioCandidate = {
  change_pct: number;
  change_value: number;
  direction: "up" | "down";
  benchmark_change_pct: number | null;
  /// Lo que más movió la cartera (por contribución).
  moves: { symbol: string; change_pct: number }[];
};

export type UserMoves = {
  user_id: string;
  moves: MoveCandidate[];
  portfolio: PortfolioCandidate | null;
};

/// Umbral de variación diaria (%), por sensibilidad.
export const thresholds: Record<Sensitivity, { stock: number; etf: number; portfolio: number }> = {
  low: { stock: 8, etf: 5, portfolio: 4 },
  normal: { stock: 5, etf: 3, portfolio: 3 },
  high: { stock: 3, etf: 2, portfolio: 2 },
};

/// Una posición tiene que pesar al menos esto para avisar por ella.
export const minWeightPct = 3;

/// Con menos cobertura de precios que esto, el % de la cartera no es
/// confiable y no se avisa.
export const minPortfolioCoverage = 0.8;

export const benchmarkSymbol = "^GSPC";

type AssetClass = "stock" | "etf" | null;

/// Cripto queda afuera en v1 (decisión D4): obligaría a mirar 24/7.
export function assetClass(q: Quote): AssetClass {
  if (q.symbol.startsWith("^")) return null;
  switch (q.quoteType) {
    case "ETF":
    case "MUTUALFUND":
      return "etf";
    case "CRYPTOCURRENCY":
    case "CURRENCY":
    case "FUTURE":
    case "INDEX":
      return null;
    default:
      return q.symbol.endsWith("-USD") ? null : "stock";
  }
}

export function computeMoves(holdings: Holding[], quotes: Map<string, Quote>): UserMoves[] {
  const byUser = new Map<string, Holding[]>();
  for (const h of holdings) {
    if (!(h.quantity > 0)) continue;
    const list = byUser.get(h.user_id) ?? [];
    list.push(h);
    byUser.set(h.user_id, list);
  }
  const benchmark = quotes.get(benchmarkSymbol)?.changePct ?? null;
  const out: UserMoves[] = [];

  for (const [userId, list] of byUser) {
    const prefs = list[0];
    const t = thresholds[prefs.sensitivity] ?? thresholds.normal;
    const priced = list
      .map((h) => ({ h, q: quotes.get(h.symbol) }))
      .filter((x): x is { h: Holding; q: Quote } => !!x.q && x.q.prevClose !== null && x.q.prevClose > 0);
    if (priced.length === 0) continue;

    const total = priced.reduce((s, x) => s + x.h.quantity * x.q.price, 0);
    const prevTotal = priced.reduce((s, x) => s + x.h.quantity * x.q.prevClose!, 0);
    if (!(total > 0) || !(prevTotal > 0)) continue;

    const moves: MoveCandidate[] = [];
    if (prefs.big_moves) {
      for (const { h, q } of priced) {
        const cls = assetClass(q);
        if (!cls) continue;
        const change = ((q.price - q.prevClose!) / q.prevClose!) * 100;
        const weight = (h.quantity * q.price / total) * 100;
        const limit = t[cls];
        if (weight < minWeightPct || Math.abs(change) < limit) continue;
        moves.push({
          symbol: h.symbol,
          change_pct: round(change, 2),
          weight_pct: round(weight, 1),
          direction: change >= 0 ? "up" : "down",
          level: Math.abs(change) >= 2 * limit ? 2 : 1,
        });
      }
      moves.sort((a, b) => Math.abs(b.change_pct) * b.weight_pct - Math.abs(a.change_pct) * a.weight_pct);
    }

    let portfolio: PortfolioCandidate | null = null;
    if (prefs.portfolio_moves && priced.length / list.length >= minPortfolioCoverage) {
      const change = ((total - prevTotal) / prevTotal) * 100;
      if (Math.abs(change) >= t.portfolio) {
        const drivers = priced
          .map(({ h, q }) => ({
            symbol: h.symbol,
            change_pct: round(((q.price - q.prevClose!) / q.prevClose!) * 100, 2),
            contribution: h.quantity * (q.price - q.prevClose!),
          }))
          // Solo lo que empujó para el mismo lado que la cartera.
          .filter((d) => Math.sign(d.contribution) === Math.sign(change) && Math.abs(d.change_pct) >= 1)
          .sort((a, b) => Math.abs(b.contribution) - Math.abs(a.contribution))
          .slice(0, 3)
          .map(({ symbol, change_pct }) => ({ symbol, change_pct }));
        portfolio = {
          change_pct: round(change, 2),
          change_value: round(total - prevTotal, 2),
          direction: change >= 0 ? "up" : "down",
          benchmark_change_pct: benchmark === null ? null : round(benchmark, 2),
          moves: drivers,
        };
      }
    }

    if (moves.length > 0 || portfolio) out.push({ user_id: userId, moves, portfolio });
  }
  return out;
}

function round(v: number, decimals: number): number {
  const f = 10 ** decimals;
  return Math.round(v * f) / f;
}

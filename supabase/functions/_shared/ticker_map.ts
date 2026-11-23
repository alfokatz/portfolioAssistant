// De qué empresa se buscan las noticias de un símbolo (capa 1 de las noticias
// por ticker): una cotización local de una empresa extranjera (`AAPL.BA` CEDEAR,
// `SHEL.L`, `SHOP.TO`, `MELI.MX`...) no tiene prensa propia; la que importa es
// la de la empresa de EE. UU. que está atrás. Vale para cualquier mercado.
//
// 1. Tabla `ticker_news_map` (excepciones, casi vacía): manda siempre.
//    `kind = local` = sin subyacente: se busca con su propio nombre.
// 2. Sin fila: heurística "quitar el sufijo de bolsa", válida solo si el
//    símbolo base existe en `sec_ticker_cik` (es un emisor de EE. UU. de
//    verdad). Si no, el propio símbolo: nunca se adivina. Las clases (.A/.B/.C)
//    no son bolsa y no se tocan.
//
// La nota se muestra igual con el ticker del usuario (la caché compartida es
// por subyacente: AAPL y AAPL.BA comparten entrada).

import type { Deps } from "./common.ts";
import { normalizeTicker } from "./sec.ts";

export type UnderlyingKind = "self" | "alias" | "heuristic" | "local";
export type Resolved = { symbol: string; underlying: string; kind: UnderlyingKind };

export type MapRow = { ticker: string; underlying: string | null; kind: "alias" | "local" };

/// Sufijo de bolsa: 1-3 letras tras el punto, salvo las clases A/B/C.
const EXCH = /\.(?![ABC]$)[A-Z]{1,3}$/;

/// Heurística por defecto: el símbolo sin sufijo de bolsa (null si no tiene).
export const stripSuffix = (symbol: string): string | null => {
  const s = symbol.trim().toUpperCase();
  return EXCH.test(s) ? s.replace(EXCH, "") : null;
};

/// Puro. [row] = fila de la tabla (si hay); [secKnown] = el candidato de la
/// heurística existe en `sec_ticker_cik`.
export function pickUnderlying(symbol: string, row: MapRow | null, secKnown: boolean): Resolved {
  const s = symbol.trim().toUpperCase();
  if (!EXCH.test(s)) return { symbol: s, underlying: s, kind: "self" };
  if (row) {
    return row.underlying
      ? { symbol: s, underlying: row.underlying, kind: "alias" }
      : { symbol: s, underlying: s, kind: "local" };
  }
  const candidate = stripSuffix(s);
  if (candidate && secKnown) return { symbol: s, underlying: candidate, kind: "heuristic" };
  return { symbol: s, underlying: s, kind: "self" };
}

/// Resuelve [symbols] en lote (2 consultas como máximo). Nunca lanza: ante un
/// error de base, cada símbolo queda como es.
export async function resolveUnderlyings(
  deps: Pick<Deps, "db">,
  symbols: string[],
): Promise<Map<string, Resolved>> {
  const out = new Map<string, Resolved>();
  const ba = [...new Set(symbols.map((s) => s.trim().toUpperCase()).filter((s) => EXCH.test(s)))];
  for (const s of symbols) {
    const u = s.trim().toUpperCase();
    if (!EXCH.test(u)) out.set(u, pickUnderlying(u, null, false));
  }
  if (ba.length === 0) return out;
  const rows = new Map<string, MapRow>();
  try {
    const { data } = await deps.db.from("ticker_news_map").select("ticker, underlying, kind").in("ticker", ba);
    for (const r of (data ?? []) as MapRow[]) rows.set(r.ticker, r);
  } catch (e) {
    console.error("[ticker_map] table", String(e));
  }
  const unknown = ba.filter((s) => !rows.has(s));
  const known = new Set<string>();
  if (unknown.length > 0) {
    try {
      const candidates = [...new Set(unknown.map((s) => normalizeTicker(stripSuffix(s)!)))];
      const { data } = await deps.db.from("sec_ticker_cik").select("ticker").in("ticker", candidates);
      for (const r of (data ?? []) as { ticker: string }[]) known.add(r.ticker);
    } catch (e) {
      console.error("[ticker_map] sec_ticker_cik", String(e));
    }
  }
  for (const s of ba) {
    const candidate = stripSuffix(s);
    out.set(s, pickUnderlying(s, rows.get(s) ?? null, candidate ? known.has(normalizeTicker(candidate)) : false));
  }
  return out;
}

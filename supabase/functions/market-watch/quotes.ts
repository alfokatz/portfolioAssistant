// Cotizaciones del servidor, en lote: Yahoo `v7/finance/quote` (hasta 50
// símbolos por pedido, con la sesión cookie + crumb del proxy `yahoo`) y,
// para lo que falte, Finnhub `/quote` de a uno.
//
// Ojo (plan D3): los planes gratis de las dos fuentes no son para uso
// comercial. Antes del lanzamiento hay que pasar a una fuente con licencia;
// cambia solo este archivo.

import type { Deps } from "../_shared/common.ts";
import { getSession, yahooSessionConfig } from "../_shared/yahoo_session.ts";

export type Quote = {
  symbol: string;
  price: number;
  prevClose: number | null;
  changePct: number | null;
  currency: string | null;
  /// REGULAR, PRE, POST, CLOSED…
  marketState: string | null;
  /// EQUITY, ETF, MUTUALFUND, CRYPTOCURRENCY…
  quoteType: string | null;
};

export const quotesConfig = {
  yahooQuoteUrl: "https://query2.finance.yahoo.com/v7/finance/quote",
  batchSize: 50,
  finnhubQuoteUrl: "https://finnhub.io/api/v1/quote",
  /// Finnhub free: 60/min para toda la app. El respaldo es solo para las
  /// alertas, y con tope.
  finnhubMaxPerRun: 30,
};

const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

export function parseYahooQuotes(body: unknown): Quote[] {
  const result = (body as { quoteResponse?: { result?: unknown[] } })?.quoteResponse?.result;
  if (!Array.isArray(result)) return [];
  const out: Quote[] = [];
  for (const r of result as Record<string, unknown>[]) {
    const price = num(r.regularMarketPrice);
    const symbol = typeof r.symbol === "string" ? r.symbol : null;
    if (!symbol || price === null || price <= 0) continue;
    const prevClose = num(r.regularMarketPreviousClose);
    out.push({
      symbol,
      price,
      prevClose,
      changePct: num(r.regularMarketChangePercent) ??
        (prevClose ? ((price - prevClose) / prevClose) * 100 : null),
      currency: typeof r.currency === "string" ? r.currency : null,
      marketState: typeof r.marketState === "string" ? r.marketState : null,
      quoteType: typeof r.quoteType === "string" ? r.quoteType : null,
    });
  }
  return out;
}

async function yahooBatch(deps: Pick<Deps, "fetch" | "now">, symbols: string[]): Promise<Quote[]> {
  for (let attempt = 0; attempt < 2; attempt++) {
    const session = await getSession(deps, attempt > 0);
    const url = new URL(quotesConfig.yahooQuoteUrl);
    url.searchParams.set("symbols", symbols.join(","));
    if (session) url.searchParams.set("crumb", session.crumb);
    let res: Response;
    try {
      res = await deps.fetch(url.toString(), {
        headers: {
          "User-Agent": yahooSessionConfig.userAgent,
          Accept: "application/json",
          ...(session ? { Cookie: session.cookie } : {}),
        },
      });
    } catch {
      return [];
    }
    // Crumb vencido: sesión nueva y una vez más.
    if (res.status === 401 && attempt === 0) {
      await res.body?.cancel();
      continue;
    }
    if (res.status !== 200) {
      await res.body?.cancel();
      return [];
    }
    try {
      return parseYahooQuotes(await res.json());
    } catch {
      return [];
    }
  }
  return [];
}

async function finnhubQuote(deps: Pick<Deps, "fetch" | "env">, symbol: string): Promise<Quote | null> {
  const token = deps.env("FINNHUB_API_KEY");
  if (!token) return null;
  const url = new URL(quotesConfig.finnhubQuoteUrl);
  url.searchParams.set("symbol", symbol);
  url.searchParams.set("token", token);
  try {
    const res = await deps.fetch(url.toString());
    if (res.status !== 200) {
      await res.body?.cancel();
      return null;
    }
    const b = await res.json() as Record<string, unknown>;
    const price = num(b.c);
    if (price === null || price <= 0) return null;
    return {
      symbol,
      price,
      prevClose: num(b.pc),
      changePct: num(b.dp),
      currency: null,
      marketState: null,
      quoteType: null,
    };
  } catch {
    return null;
  }
}

/// Cotizaciones de [symbols]. [fallbackFor]: los que, si Yahoo no los
/// trae, se piden a Finnhub (los de las alertas: los movimientos fuertes
/// pueden esperar a la próxima corrida).
export async function fetchQuotes(
  deps: Pick<Deps, "fetch" | "now" | "env">,
  symbols: string[],
  fallbackFor: Set<string> = new Set(),
): Promise<Map<string, Quote>> {
  const unique = [...new Set(symbols)];
  const out = new Map<string, Quote>();
  for (let i = 0; i < unique.length; i += quotesConfig.batchSize) {
    for (const q of await yahooBatch(deps, unique.slice(i, i + quotesConfig.batchSize))) {
      out.set(q.symbol, q);
    }
  }
  const missing = unique.filter((s) => !out.has(s) && fallbackFor.has(s)).slice(0, quotesConfig.finnhubMaxPerRun);
  for (const s of missing) {
    const q = await finnhubQuote(deps, s);
    if (q) out.set(s, q);
  }
  return out;
}

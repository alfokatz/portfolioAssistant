// Titulares por empresa para Porty (card de noticias, informe semanal),
// plan Gold: GDELT DOC 2.0 filtrado por los medios permitidos
// (`news_source_allowlist`). Reemplaza a Google News RSS y Finnhub
// `/company-news` cuando `app_config.news_provider = v2`.
//
// La app llama GET /functions/v1/headlines?tickers=NVDA,AAPL
//   [&names=NVIDIA|Apple][&from=YYYY-MM-DD&to=YYYY-MM-DD] con su JWT (hasta
//   10 tickers en UNA consulta a GDELT: el informe semanal pide toda la
//   cartera de una vez). Devuelve solo título, medio,
// fecha, idioma y link (nunca imágenes ni texto del artículo).
//
// GDELT se consulta por NOMBRE de empresa (el de la SEC, limpio, o [name]),
// con un limitador global de 1 pedido cada ~5 s y caché compartida: 30 min
// para lo reciente, 24 h para una semana ya cerrada.

import { bearer, corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { goldAllowed, readCache, writeCache } from "../_shared/data_cache.ts";
import { assignByName, gdeltFetch, gdeltUrl, type Headline, newsAllowlist, parseArticles, pressName } from "../_shared/gdelt.ts";
import { normalizeTicker } from "../_shared/sec.ts";
import { resolveCik } from "../_shared/sec_data.ts";

export const config = {
  recentTtlSeconds: 30 * 60,
  closedWindowTtlSeconds: 24 * 60 * 60,
  ratePerMinute: 30,
  maxItemsPerTicker: 12,
  maxTickers: 10,
};

export type HeadlinesBody = {
  status: "ok" | "empty";
  /// Ticker → nombre con el que se buscó.
  names: Record<string, string>;
  by_ticker: Record<string, Headline[]>;
  as_of: string;
  source: { name: string; url: string };
};

const isoDay = /^\d{4}-\d{2}-\d{2}$/;

/// Nombre con el que la prensa nombra a [ticker], a partir del de la SEC
/// (refresca el mapa ticker → CIK si hace falta). Sin dato: el ticker.
async function companyName(deps: Deps, ticker: string): Promise<string | null> {
  try {
    const row = await resolveCik(deps, ticker);
    return row ? pressName(row.title) : null;
  } catch {
    return null;
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return typedError(405, "method_not_allowed", "GET only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  const url = new URL(req.url);
  const raw = (url.searchParams.get("tickers") ?? url.searchParams.get("ticker") ?? "").split(",");
  const tickers = [...new Set(raw.map((t) => t.trim()).filter(Boolean))];
  if (
    tickers.length === 0 || tickers.length > config.maxTickers ||
    !tickers.every((t) => /^[A-Za-z0-9.\-]{1,10}$/.test(t))
  ) {
    return typedError(400, "invalid_ticker", `1-${config.maxTickers} tickers expected`);
  }
  const symbols = tickers.map(normalizeTicker).sort();
  const givenNames = (url.searchParams.get("names") ?? url.searchParams.get("name") ?? "").split("|");
  const from = url.searchParams.get("from");
  const to = url.searchParams.get("to");
  if ((from || to) && !(from && to && isoDay.test(from) && isoDay.test(to) && from < to)) {
    return typedError(400, "invalid_window", "from/to must be YYYY-MM-DD with from < to");
  }

  if (!(await goldAllowed(deps, userId, symbols))) {
    return typedError(403, "plan_required", "Gold required", { required_plan: "gold" });
  }
  const rate = await deps.db.rpc("rate_limit_hit", {
    p_user_id: userId,
    p_bucket: "headlines",
    p_per_minute: config.ratePerMinute,
  });
  if (rate.data === false) return typedError(429, "rate_limited", "Too many requests");

  const started = Date.now();
  const key = `gdelt:${symbols.join(",")}|${from ?? ""}|${to ?? ""}`;
  const today = new Date(deps.now()).toISOString().slice(0, 10);
  const ttl = to && to <= today ? config.closedWindowTtlSeconds : config.recentTtlSeconds;
  const hit = await readCache<HeadlinesBody>(deps, key);
  if (hit && hit.ageSeconds < ttl) {
    log("hit", started);
    return json(200, hit.body, { "x-cache": "hit" });
  }

  const names: Record<string, string> = {};
  for (const [i, t] of tickers.entries()) {
    const given = (givenNames[i] ?? "").trim().slice(0, 80);
    const symbol = normalizeTicker(t);
    names[symbol] = given.length >= 2 ? pressName(given) : await companyName(deps, symbol) ?? symbol;
  }
  const allow = await newsAllowlist(deps);

  let articles: Headline[];
  try {
    const window = from && to ? { from: new Date(`${from}T00:00:00Z`), to: new Date(`${to}T00:00:00Z`) } : {};
    articles = parseArticles(await gdeltFetch(deps, gdeltUrl(Object.values(names), [...allow.keys()], window)), allow);
  } catch (e) {
    console.error("[headlines]", symbols.join(","), e);
    if (hit) {
      log("stale", started);
      return json(200, hit.body, { "x-cache": "stale" });
    }
    log("error", started);
    return typedError(502, "upstream_unavailable", "GDELT unavailable");
  }

  const byTicker = assignByName(articles, names);
  for (const t of Object.keys(byTicker)) byTicker[t] = byTicker[t].slice(0, config.maxItemsPerTicker);
  const body: HeadlinesBody = {
    status: Object.values(byTicker).some((l) => l.length > 0) ? "ok" : "empty",
    names,
    by_ticker: byTicker,
    as_of: new Date(deps.now()).toISOString(),
    source: { name: "GDELT Project", url: "https://www.gdeltproject.org/" },
  };
  await writeCache(deps, key, body);
  log("miss", started);
  return json(200, body, { "x-cache": "miss" });
}

function log(cache: string, started: number) {
  console.log(JSON.stringify({ fn: "headlines", cache, ms: Date.now() - started }));
}

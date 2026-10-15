// "Qué está pasando y por qué" para Porty (tool `get_news`, plan Gold):
// la herramienta `web_search` de OpenAI (Responses API), llamada desde el
// servidor, restringida a una lista de medios permitidos
// (`news_source_allowlist`) y con citas. Reemplaza a Google News RSS y a
// Finnhub `/company-news` cuando `app_config.news_provider = v2`.
//
// La app manda POST /functions/v1/news-context
//   { tickers?: ["NVDA"], names?: {NVDA: "NVIDIA"}, topic?: "...",
//     question?: "...", lang: "es" | "en" }
// con su JWT (y `x-porty-turn-id` si lo tiene).
//
// - No se baja ni se copia el texto de ningún artículo: el contexto y las
//   citas los trae la búsqueda web.
// - Caché compartida de 45 min: sin pregunta, POR EMPRESA (cada una se busca
//   aparte y en paralelo, ver [partsOf]); con pregunta, por (tickers|tema,
//   pregunta, idioma). Un hit no gasta cupo ni llama a OpenAI.
// - Topes: 1 pedido por turno (sin pregunta, hasta 5 búsquedas: una por
//   empresa que no estaba en caché) y un tope diario de pedidos por plan
//   (`plan_limits.news_context_per_day`).
// - Costo: cada búsqueda se suma al turno en `ai_turn_usage`.

import { bearer, corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { goldAllowed, readCache, writeCache } from "../_shared/data_cache.ts";
import { pressName } from "../_shared/gdelt.ts";
import { resolveCik } from "../_shared/sec_data.ts";
import { readResponse, type ResponsesOutput } from "../_shared/openai_responses.ts";

export const config = {
  openAiUrl: "https://api.openai.com/v1/responses",
  /// Modelo con `web_search` (override: NEWS_CONTEXT_MODEL). Tiene que
  /// aceptar `filters.allowed_domains`: gpt-4.1-mini NO lo acepta (400).
  defaultModel: "gpt-5-mini",
  cacheTtlSeconds: 45 * 60,
  /// Sin novedades: se vuelve a buscar antes (puede haber sido un mal momento).
  emptyCacheTtlSeconds: 10 * 60,
  ratePerMinute: 10,
  /// "¿Por qué se movió mi cartera?" pide las que más movieron: con 3 quedaban
  /// afuera la mitad de las posiciones de una cartera chica.
  maxTickers: 5,
  maxQuestionLength: 240,
  maxCitations: 8,
  /// Incluye el razonamiento de gpt-5-mini (~500 tokens con effort low):
  /// con 900 la respuesta quedaba cortada o vacía.
  maxOutputTokens: 2_500,
  timeoutMs: 25_000,
  /// US$ por búsqueda (developers.openai.com/api/docs/pricing, 2026-10).
  searchCallUsd: 0.01,
  /// US$ por millón de tokens [entrada, salida]; lo desconocido usa el default.
  tokenPrices: {
    "gpt-4.1-mini": [0.4, 1.6],
    "gpt-4.1": [2, 8],
    "gpt-5-mini": [0.25, 2],
    "gpt-5": [1.25, 10],
    "gpt-6-luna": [0.1, 0.5],
  } as Record<string, [number, number]>,
};

type Citation = { title: string; url: string; source: string; domain: string };

export type NewsContext = {
  status: "ok" | "empty";
  subject: string;
  summary: string[];
  citations: Citation[];
  as_of: string;
};

type Body = {
  tickers: string[];
  names: Record<string, string>;
  topic: string | null;
  question: string | null;
  lang: "es" | "en";
};

export function parseBody(raw: unknown): Body | null {
  const b = (raw ?? {}) as Record<string, unknown>;
  const tickers = Array.isArray(b.tickers)
    ? [...new Set(b.tickers.map((t) => String(t).trim().toUpperCase()).filter((t) => /^[A-Z0-9.\-]{1,10}$/.test(t)))]
    : [];
  const names: Record<string, string> = {};
  if (b.names && typeof b.names === "object") {
    for (const [k, v] of Object.entries(b.names as Record<string, unknown>)) {
      if (typeof v === "string" && v.trim()) names[k.toUpperCase()] = v.trim().slice(0, 80);
    }
  }
  const text = (v: unknown, max: number) =>
    typeof v === "string" && v.trim().length >= 3 ? v.trim().replace(/\s+/g, " ").slice(0, max) : null;
  const topic = text(b.topic, 120);
  const question = text(b.question, config.maxQuestionLength);
  if (tickers.length === 0 && !topic) return null;
  if (tickers.length > config.maxTickers) return null;
  return { tickers, names, topic, question, lang: b.lang === "en" ? "en" : "es" };
}

export function cacheKey(b: Body): string {
  const subject = b.tickers.length ? [...b.tickers].sort().join(",") : (b.topic ?? "").toLowerCase();
  const q = (b.question ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f¿?¡!.,]/g, "")
    .replace(/\s+/g, " ").trim();
  return `news:${subject}|${q}|${b.lang}`;
}

function subjectOf(b: Body): string {
  if (b.tickers.length === 0) return b.topic!;
  return b.tickers.map((t) => (b.names[t] ? `${b.names[t]} (${t})` : t)).join(", ");
}

export function prompts(b: Body, today: string): { instructions: string; input: string } {
  const language = b.lang === "en" ? "English" : "Spanish (neutral Latin American)";
  const instructions = [
    `Today is ${today}. You brief a retail investor inside a personal-finance app, using web search.`,
    `Answer in ${language}, as bullet points: each line starts with "- " and is ONE short sentence.`,
    b.tickers.length > 1
      ? `Start every bullet with the ticker it is about and the date of the event, like "- MSFT (${today}): ...". Cover EACH company asked (search each one separately); skip a company only if it had no news.`
      : `Start every bullet with the date of the event, like "- (${today}): ...".`,
    b.question
      ? "Answer the user's question in 1-5 bullets. If it asks for a date or a figure, give it exactly as the sources state it and say if it is not confirmed."
      : `Write ${Math.min(8, 3 + 2 * b.tickers.length)} bullets at most about what happened in the LAST 7 DAYS and why it matters for an investor (including what moved the stock price, if reported), most important first.`,
    "Only facts specifically about the company or topic asked (never about unrelated things with a similar name). Never use articles older than 7 days unless the question asks about an older fact.",
    "For an ETF, report what moved its market or sector this week (e.g. the S&P 500 for an S&P 500 ETF), from articles about it.",
    "Every bullet must be backed by a cited news ARTICLE (never a quote, price-history or market-data page). Prefer original reporting from major outlets. Paraphrase; never copy article text.",
    "Never give buy/sell/hold recommendations or price targets of your own; you may report what analysts said, attributed.",
    'If you find nothing relevant and recent, reply exactly: SIN_NOVEDADES',
  ].join("\n");
  const subject = subjectOf(b);
  const input = b.question
    ? `${b.question}\n(About: ${subject})`
    : b.lang === "en"
    ? `What happened with ${subject} in the last 7 days, and why does it matter?`
    : `¿Qué pasó con ${subject} en los últimos 7 días y por qué importa?`;
  return { instructions, input };
}

/// Viñetas: "- ", "• ", "* ", "– " o listas numeradas ("1. ", "2) ").
const bulletMark = /^(?:[-•*–—]|\d{1,2}[.)])\s+/;

/// Viñetas limpias: sin marcadores de cita "([medio](url))" que el modelo a
/// veces deja en el texto (las citas van aparte, clickeables) ni negritas.
/// Sin ninguna viñeta (el modelo respondió en párrafos), cada párrafo es una.
export function bullets(text: string): string[] {
  const lines = text.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
  const marked = lines.filter((l) => bulletMark.test(l));
  const picked = marked.length > 0 ? marked : lines.filter((l) => !l.includes("SIN_NOVEDADES") && !l.endsWith(":"));
  return picked
    .map((l) =>
      l.replace(bulletMark, "")
        .replace(/\*\*([^*]+)\*\*/g, "$1")
        .replace(/\s*\(\[[^\]]*\]\([^)]*\)\)/g, "")
        .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
        .replace(/\s+/g, " ")
        .trim()
    )
    .filter((l) => l.length > 0)
    .slice(0, 8);
}

const hostOf = (url: string) => {
  try {
    return new URL(url).hostname.replace(/^www\./, "").toLowerCase();
  } catch {
    return "";
  }
};

/// El medio permitido al que pertenece [host] (subdominios incluidos).
export function allowedDomain(host: string, allow: Map<string, string>): string | null {
  for (const domain of allow.keys()) {
    if (host === domain || host.endsWith(`.${domain}`)) return domain;
  }
  return null;
}

/// Páginas de cotización o históricos de precios: no son una fuente de noticias.
const quotePage = /\/(quotes?|symbol|historical|history)\b/i;

/// Citas sin repetir, solo de medios permitidos, sin parámetros de rastreo.
export function citationsOf(annotations: { url: string; title?: string }[], allow: Map<string, string>): Citation[] {
  const seen = new Set<string>();
  const out: Citation[] = [];
  for (const a of annotations) {
    let url: URL;
    try {
      url = new URL(a.url);
    } catch {
      continue;
    }
    for (const k of [...url.searchParams.keys()]) if (k.startsWith("utm_")) url.searchParams.delete(k);
    const clean = url.toString();
    const domain = allowedDomain(hostOf(clean), allow);
    if (!domain || seen.has(clean) || quotePage.test(url.pathname)) continue;
    seen.add(clean);
    out.push({ title: (a.title ?? "").trim() || allow.get(domain)!, url: clean, source: allow.get(domain)!, domain });
    if (out.length === config.maxCitations) break;
  }
  return out;
}

export function costUsd(model: string, out: ResponsesOutput): number {
  const [inPrice, outPrice] = config.tokenPrices[model] ?? config.tokenPrices[config.defaultModel];
  const calls = Math.max(out.searchCalls, 1);
  return Number(
    (calls * config.searchCallUsd + (out.inputTokens * inPrice + out.outputTokens * outPrice) / 1e6).toFixed(6),
  );
}

async function allowlist(deps: Deps): Promise<Map<string, string>> {
  const { data } = await deps.db.from("news_source_allowlist").select("domain, name").eq("enabled", true);
  return new Map((data ?? []).map((r: { domain: string; name: string }) => [r.domain, r.name]));
}

/// Sin pregunta, cada empresa se busca y se cachea por separado: "noticias
/// de MSFT", la cartera de un usuario y la de otro reusan la misma entrada,
/// y las búsquedas que faltan corren en paralelo (tarda la más lenta, no la
/// suma). Con pregunta, una sola búsqueda con todo junto.
export function partsOf(b: Body): Body[] {
  if (b.question !== null || b.tickers.length <= 1) return [b];
  return b.tickers.map((t) => ({ ...b, tickers: [t], names: b.names[t] ? { [t]: b.names[t] } : {} }));
}

/// Viñetas por empresa al juntar partes: las primeras de cada una.
const bulletsPerTicker = 3;

/// Junta los resultados de cada empresa en uno: viñetas con su ticker
/// adelante y citas intercaladas (una de cada empresa por vuelta). Con
/// [split] false (una sola parte en el pedido) devuelve esa parte tal cual.
export function mergeParts(results: NewsContext[], tickers: string[], asOf: string, split = true): NewsContext {
  if (!split && results.length === 1) return results[0];
  const summary: string[] = [];
  results.forEach((r, i) => {
    if (r.status !== "ok") return;
    for (const line of r.summary.slice(0, bulletsPerTicker)) {
      summary.push(line.startsWith(tickers[i]) ? line : `${tickers[i]} ${line}`);
    }
  });
  const citations: Citation[] = [];
  const seen = new Set<string>();
  const lists = results.map((r) => (r.status === "ok" ? r.citations : []));
  for (let round = 0; citations.length < config.maxCitations; round++) {
    let added = false;
    for (const list of lists) {
      const c = list[round];
      if (!c) continue;
      added = true;
      if (seen.has(c.url) || citations.length >= config.maxCitations) continue;
      seen.add(c.url);
      citations.push(c);
    }
    if (!added) break;
  }
  const ok = summary.length > 0 && citations.length > 0;
  return {
    status: ok ? "ok" : "empty",
    subject: results.map((r) => r.subject).join(", "),
    summary: ok ? summary : [],
    citations: ok ? citations : [],
    as_of: asOf,
  };
}

type Search = { result: NewsContext | null; calls: number; cost: number };

/// Una búsqueda web para [b]. `result` null = falló o se cortó (no se cachea).
async function search(
  deps: Deps,
  b: Body,
  ctx: { apiKey: string; model: string; allow: Map<string, string>; today: string },
): Promise<Search> {
  const { instructions, input } = prompts(b, ctx.today);
  let upstream: Response;
  try {
    upstream = await deps.fetch(config.openAiUrl, {
      method: "POST",
      headers: { Authorization: `Bearer ${ctx.apiKey}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(config.timeoutMs),
      body: JSON.stringify({
        model: ctx.model,
        instructions,
        input,
        tools: [{
          type: "web_search",
          search_context_size: "low",
          ...(ctx.allow.size > 0 ? { filters: { allowed_domains: [...ctx.allow.keys()].slice(0, 100) } } : {}),
          ...(b.lang === "es" ? { user_location: { type: "approximate", country: "AR" } } : {}),
        }],
        tool_choice: "required",
        // gpt-6-luna razona en `medium` por default: más lento y se come el
        // tope de salida antes de escribir.
        ...(/^gpt-[56]/.test(ctx.model) ? { reasoning: { effort: "low" } } : {}),
        max_output_tokens: config.maxOutputTokens,
        store: false,
      }),
    });
  } catch (e) {
    console.error("[news-context] fetch", e);
    return { result: null, calls: 0, cost: 0 };
  }
  if (!upstream.ok) {
    console.error("[news-context] upstream", upstream.status, await upstream.text());
    return { result: null, calls: 0, cost: 0 };
  }
  const out = readResponse(await upstream.json());
  const calls = Math.max(out.searchCalls, 1);
  const cost = costUsd(ctx.model, out);
  if (out.text === "") {
    // Cortada antes de escribir: no es "sin novedades", no se cachea.
    console.error("[news-context] no text", out.status, out.outputTokens);
    return { result: null, calls, cost };
  }
  const summary = out.text.trim().startsWith("SIN_NOVEDADES") ? [] : bullets(out.text);
  const citations = citationsOf(out.annotations, ctx.allow);
  if (summary.length === 0 || citations.length === 0) {
    console.log(JSON.stringify({
      fn: "news-context",
      empty: out.text.includes("SIN_NOVEDADES") ? "sin_novedades" : summary.length === 0 ? "no_bullets" : "no_citations",
      annotations: out.annotations.length,
      status: out.status,
    }));
  }
  const ok = summary.length > 0 && citations.length > 0;
  return {
    result: {
      status: ok ? "ok" : "empty",
      subject: subjectOf(b),
      // Sin resumen no hay fuentes: la app las mostraba debajo de un "no
      // encontré noticias" y parecía una contradicción.
      summary: ok ? summary : [],
      citations: ok ? citations : [],
      as_of: new Date(deps.now()).toISOString(),
    },
    calls,
    cost,
  };
}

const ttlOf = (c: NewsContext) => (c.status === "empty" ? config.emptyCacheTtlSeconds : config.cacheTtlSeconds);

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  let body: Body | null = null;
  try {
    body = parseBody(await req.json());
  } catch {
    body = null;
  }
  if (!body) return typedError(400, "invalid_body", "tickers (1-5) or topic expected");

  if (!(await goldAllowed(deps, userId, body.tickers))) {
    return typedError(403, "plan_required", "Gold required", { required_plan: "gold" });
  }

  const rate = await deps.db.rpc("rate_limit_hit", {
    p_user_id: userId,
    p_bucket: "news_context",
    p_per_minute: config.ratePerMinute,
  });
  if (rate.data === false) return typedError(429, "rate_limited", "Too many requests");

  const started = Date.now();
  const parts = partsOf(body);
  const split = parts.length > 1;
  const tickers = parts.map((p) => p.tickers[0] ?? "");
  const keys = parts.map(cacheKey);
  const hits = await Promise.all(keys.map((k) => readCache<NewsContext>(deps, k)));
  const missing = parts.map((_, i) => i).filter((i) => {
    const hit = hits[i];
    return !hit || hit.ageSeconds >= ttlOf(hit.body);
  });
  const asOf = () => new Date(deps.now()).toISOString();
  /// Lo que haya en caché (vigente o vencido) de cada parte, junto.
  const fromCache = () => {
    const have = hits.map((h, i) => (h ? i : -1)).filter((i) => i >= 0);
    return have.length === 0 ? null : mergeParts(have.map((i) => hits[i]!.body), have.map((i) => tickers[i]), asOf(), split);
  };
  if (missing.length === 0) {
    log("hit", started, 0);
    return json(200, fromCache(), { "x-cache": "hit" });
  }

  const turnId = req.headers.get("x-porty-turn-id");
  const used = await deps.db.rpc("turn_web_search_calls", { p_user_id: userId, p_turn_id: turnId });
  if (Number(used.data ?? 0) >= 1) {
    const cached = fromCache();
    if (cached) return json(200, cached, { "x-cache": "stale" });
    return typedError(429, "turn_limit", "One news search per turn");
  }
  const daily = await deps.db.rpc("news_context_hit", { p_user_id: userId });
  if (daily.data !== true) {
    const cached = fromCache();
    if (cached) return json(200, cached, { "x-cache": "stale" });
    return typedError(429, "daily_limit", "Daily news search limit reached");
  }

  const apiKey = deps.env("OPENAI_API_KEY");
  if (!apiKey) return typedError(503, "unavailable", "OpenAI key not configured");
  // Sin nombre, la búsqueda por ticker sola trae poco ("MELI"): el de la SEC.
  const unnamed = [...new Set(missing.flatMap((i) => parts[i].tickers))].filter((t) => !body!.names[t]);
  const [allow] = await Promise.all([
    allowlist(deps),
    ...unnamed.map(async (t) => {
      try {
        const row = await resolveCik(deps, t);
        if (!row) return;
        const name = pressName(row.title);
        body!.names[t] = name;
        for (const p of parts) if (p.tickers.includes(t)) p.names[t] = name;
      } catch {
        // sin nombre: se busca por ticker
      }
    }),
  ]);
  const ctx = {
    apiKey,
    allow: allow as Map<string, string>,
    model: deps.env("NEWS_CONTEXT_MODEL") ?? config.defaultModel,
    today: new Date(deps.now()).toISOString().slice(0, 10),
  };
  const searches = await Promise.all(missing.map((i) => search(deps, parts[i], ctx)));

  const calls = searches.reduce((n, s) => n + s.calls, 0);
  const cost = Number(searches.reduce((n, s) => n + s.cost, 0).toFixed(6));
  if (calls > 0) {
    const record = await deps.db.rpc("record_web_search_usage", {
      p_user_id: userId,
      p_turn_id: turnId,
      p_calls: calls,
      p_cost_usd: cost,
    });
    if (record.error) console.error("[news-context] record usage", record.error.message);
  }

  const results: (NewsContext | null)[] = hits.map((h) => h?.body ?? null);
  let searched = 0;
  await Promise.all(missing.map((i, j) => {
    const r = searches[j].result;
    if (!r) return; // falló: queda el dato vencido, si había
    results[i] = r;
    searched++;
    // Lo vacío también se cachea: evita repetir una búsqueda sin novedades.
    return writeCache(deps, keys[i], r);
  }));
  const have = results.map((r, i) => (r ? i : -1)).filter((i) => i >= 0);
  if (have.length === 0) return typedError(502, "upstream_failed", "Search failed");
  log(searched === missing.length ? "miss" : "partial", started, calls, cost);
  return json(200, mergeParts(have.map((i) => results[i]!), have.map((i) => tickers[i]), asOf(), split), {
    "x-cache": searched === 0 ? "stale" : "miss",
  });
}

/// Una línea por pedido (sin usuario ni pregunta) para medir caché, latencia
/// y costo en los logs.
function log(cache: string, started: number, calls: number, cost = 0) {
  console.log(JSON.stringify({ fn: "news-context", cache, ms: Date.now() - started, calls, cost_usd: cost }));
}

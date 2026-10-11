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
// - Caché compartida por (tickers|tema, pregunta, idioma), 45 min: un hit no
//   gasta cupo ni llama a OpenAI.
// - Topes: 1 búsqueda por turno y un tope diario por plan
//   (`plan_limits.news_context_per_day`).
// - Costo: cada búsqueda se suma al turno en `ai_turn_usage`.

import { bearer, corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { goldAllowed, readCache, writeCache } from "../_shared/data_cache.ts";
import { pressName } from "../_shared/gdelt.ts";
import { resolveCik } from "../_shared/sec_data.ts";

export const config = {
  openAiUrl: "https://api.openai.com/v1/responses",
  /// Modelo con `web_search` (override: NEWS_CONTEXT_MODEL). Tiene que
  /// aceptar `filters.allowed_domains`: gpt-4.1-mini NO lo acepta (400).
  defaultModel: "gpt-5-mini",
  cacheTtlSeconds: 45 * 60,
  /// Sin novedades: se vuelve a buscar antes (puede haber sido un mal momento).
  emptyCacheTtlSeconds: 10 * 60,
  ratePerMinute: 10,
  maxTickers: 3,
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
    b.question
      ? "Answer the user's question in 1-5 bullets. If it asks for a date or a figure, give it exactly as the sources state it and say if it is not confirmed."
      : "Write 5-8 bullets about what happened in the LAST 7 DAYS and why it matters for an investor, most important first.",
    "Only facts specifically about the company or topic asked (never about unrelated things with a similar name).",
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

type ResponsesOutput = {
  /// `incomplete` = se cortó (p. ej. el razonamiento se comió el tope).
  status: string;
  text: string;
  annotations: { url: string; title?: string }[];
  searchCalls: number;
  inputTokens: number;
  outputTokens: number;
};

// deno-lint-ignore no-explicit-any
export function readResponse(body: any): ResponsesOutput {
  let text = "";
  const annotations: { url: string; title?: string }[] = [];
  let searchCalls = 0;
  for (const item of Array.isArray(body?.output) ? body.output : []) {
    if (item?.type === "web_search_call") searchCalls++;
    if (item?.type !== "message") continue;
    for (const part of Array.isArray(item.content) ? item.content : []) {
      if (part?.type !== "output_text") continue;
      text += String(part.text ?? "");
      for (const a of Array.isArray(part.annotations) ? part.annotations : []) {
        if (a?.type === "url_citation" && typeof a.url === "string") annotations.push({ url: a.url, title: a.title });
      }
    }
  }
  return {
    status: String(body?.status ?? ""),
    text: text.trim(),
    annotations,
    searchCalls,
    inputTokens: Number(body?.usage?.input_tokens ?? 0),
    outputTokens: Number(body?.usage?.output_tokens ?? 0),
  };
}

/// Viñetas limpias: sin marcadores de cita "([medio](url))" que el modelo a
/// veces deja en el texto (las citas van aparte, clickeables).
export function bullets(text: string): string[] {
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => /^[-•*]\s+/.test(l))
    .map((l) =>
      l.replace(/^[-•*]\s+/, "")
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
  if (!body) return typedError(400, "invalid_body", "tickers (1-3) or topic expected");

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
  const key = cacheKey(body);
  const hit = await readCache<NewsContext>(deps, key);
  const ttl = hit?.body.status === "empty" ? config.emptyCacheTtlSeconds : config.cacheTtlSeconds;
  if (hit && hit.ageSeconds < ttl) {
    log("hit", started, 0);
    return json(200, hit.body, { "x-cache": "hit" });
  }

  const turnId = req.headers.get("x-porty-turn-id");
  const used = await deps.db.rpc("turn_web_search_calls", { p_user_id: userId, p_turn_id: turnId });
  if (Number(used.data ?? 0) >= 1) {
    if (hit) return json(200, hit.body, { "x-cache": "stale" });
    return typedError(429, "turn_limit", "One news search per turn");
  }
  const daily = await deps.db.rpc("news_context_hit", { p_user_id: userId });
  if (daily.data !== true) {
    if (hit) return json(200, hit.body, { "x-cache": "stale" });
    return typedError(429, "daily_limit", "Daily news search limit reached");
  }

  const apiKey = deps.env("OPENAI_API_KEY");
  if (!apiKey) return typedError(503, "unavailable", "OpenAI key not configured");
  // Sin nombre, la búsqueda por ticker sola trae poco ("MELI"): el de la SEC.
  for (const t of body.tickers) {
    if (body.names[t]) continue;
    try {
      const row = await resolveCik(deps, t);
      if (row) body.names[t] = pressName(row.title);
    } catch {
      // sin nombre: se busca por ticker
    }
  }
  const allow = await allowlist(deps);
  const model = deps.env("NEWS_CONTEXT_MODEL") ?? config.defaultModel;
  const today = new Date(deps.now()).toISOString().slice(0, 10);
  const { instructions, input } = prompts(body, today);

  let upstream: Response;
  try {
    upstream = await deps.fetch(config.openAiUrl, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(config.timeoutMs),
      body: JSON.stringify({
        model,
        instructions,
        input,
        tools: [{
          type: "web_search",
          search_context_size: "low",
          ...(allow.size > 0 ? { filters: { allowed_domains: [...allow.keys()].slice(0, 100) } } : {}),
          ...(body.lang === "es" ? { user_location: { type: "approximate", country: "AR" } } : {}),
        }],
        tool_choice: "required",
        ...(model.startsWith("gpt-5") ? { reasoning: { effort: "low" } } : {}),
        max_output_tokens: config.maxOutputTokens,
        store: false,
      }),
    });
  } catch (e) {
    console.error("[news-context] fetch", e);
    return stale(hit) ?? typedError(502, "upstream_failed", "Search failed");
  }
  if (!upstream.ok) {
    console.error("[news-context] upstream", upstream.status, await upstream.text());
    return stale(hit) ?? typedError(502, "upstream_failed", "Search failed");
  }
  const out = readResponse(await upstream.json());
  const cost = costUsd(model, out);
  const record = await deps.db.rpc("record_web_search_usage", {
    p_user_id: userId,
    p_turn_id: turnId,
    p_calls: Math.max(out.searchCalls, 1),
    p_cost_usd: cost,
  });
  if (record.error) console.error("[news-context] record usage", record.error.message);

  if (out.text === "") {
    // Cortada antes de escribir: no es "sin novedades", no se cachea.
    console.error("[news-context] no text", out.status, out.outputTokens);
    return stale(hit) ?? typedError(502, "upstream_failed", "Search returned no answer");
  }
  const summary = out.text.includes("SIN_NOVEDADES") ? [] : bullets(out.text);
  const citations = citationsOf(out.annotations, allow);
  if (summary.length === 0 || citations.length === 0) {
    console.log(JSON.stringify({
      fn: "news-context",
      empty: out.text.includes("SIN_NOVEDADES") ? "sin_novedades" : summary.length === 0 ? "no_bullets" : "no_citations",
      annotations: out.annotations.length,
      status: out.status,
    }));
  }
  const result: NewsContext = {
    status: summary.length > 0 && citations.length > 0 ? "ok" : "empty",
    subject: subjectOf(body),
    summary: citations.length > 0 ? summary : [],
    citations,
    as_of: new Date(deps.now()).toISOString(),
  };
  // Lo vacío también se cachea: evita repetir una búsqueda sin novedades.
  await writeCache(deps, key, result);
  log("miss", started, Math.max(out.searchCalls, 1), cost);
  return json(200, result, { "x-cache": "miss" });
}

function stale(hit: { body: NewsContext } | null): Response | null {
  return hit ? json(200, hit.body, { "x-cache": "stale" }) : null;
}

/// Una línea por pedido (sin usuario ni pregunta) para medir caché, latencia
/// y costo en los logs.
function log(cache: string, started: number, calls: number, cost = 0) {
  console.log(JSON.stringify({ fn: "news-context", cache, ms: Date.now() - started, calls, cost_usd: cost }));
}

// Búsqueda web de Porty (tool `search_web`): para datos que ninguna otra
// fuente de la app tiene, como el precio actual de un producto para una
// meta de compra. La key de OpenAI vive en los secrets; la app manda
// POST /functions/v1/web-search {query} con su JWT.
//
// - Caché compartida por consulta normalizada (24 h, `web_search_cache`):
//   un hit no gasta cupo ni llama a OpenAI.
// - Tope diario por plan (`plan_limits.web_searches_per_day`, RPC
//   `web_search_hit`) y rate limit por minuto.
// - Devuelve una respuesta corta + las fuentes citadas (url_citation): el
//   modelo de Porty solo puede citar lo que viene acá.

import { bearer, corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";

export const config = {
  openAiUrl: "https://api.openai.com/v1/chat/completions",
  /// Modelo con búsqueda web de Chat Completions (override: WEB_SEARCH_MODEL).
  defaultModel: "gpt-4o-mini-search-preview",
  cacheTtlSeconds: 24 * 60 * 60,
  ratePerMinute: 10,
  maxQueryLength: 200,
  maxSources: 4,
  maxAnswerTokens: 350,
};

const systemPrompt =
  "You answer ONE factual lookup for a personal-finance app, using web " +
  "search. Reply in Spanish, at most 70 words, plain text, no markdown. " +
  "For a product price, give the current official price in USD in the US " +
  "(and the range across models/configurations if it varies), and say if " +
  "the product could not be found or does not exist. Never give investment " +
  "advice. If the query is not about prices, products, costs of living, " +
  "fees, rates or other personal-finance facts, reply exactly: FUERA_DE_TEMA";

/// Misma consulta, misma clave: minúsculas, sin espacios repetidos.
export function queryKey(query: string): string {
  return query.toLowerCase().normalize("NFKC").replace(/\s+/g, " ").trim();
}

type Source = { title: string; url: string };

/// Las fuentes que citó el modelo (url_citation), sin repetidas.
export function sourcesOf(message: Record<string, unknown> | undefined): Source[] {
  const annotations = (message?.annotations as Record<string, unknown>[] | undefined) ?? [];
  const seen = new Set<string>();
  const out: Source[] = [];
  for (const a of annotations) {
    const c = a?.url_citation as { url?: string; title?: string } | undefined;
    if (!c?.url || seen.has(c.url)) continue;
    seen.add(c.url);
    out.push({ title: c.title ?? new URL(c.url).hostname, url: c.url });
    if (out.length === config.maxSources) break;
  }
  return out;
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  let query = "";
  try {
    const body = await req.json();
    query = typeof body?.query === "string" ? body.query.trim() : "";
  } catch {
    return typedError(400, "invalid_body", "JSON body with `query` expected");
  }
  if (query.length < 3 || query.length > config.maxQueryLength) {
    return typedError(400, "invalid_query", "query must be 3-200 characters");
  }

  const rate = await deps.db.rpc("rate_limit_hit", {
    p_user_id: userId,
    p_bucket: "web_search",
    p_per_minute: config.ratePerMinute,
  });
  if (rate.data === false) return typedError(429, "rate_limited", "Too many requests");

  const key = queryKey(query);
  const { data: cached } = await deps.db
    .from("web_search_cache")
    .select("body, fetched_at")
    .eq("query_key", key)
    .maybeSingle();
  if (cached && (deps.now() - Date.parse(cached.fetched_at)) / 1000 < config.cacheTtlSeconds) {
    return json(200, cached.body, { "x-cache": "hit" });
  }

  const allowed = await deps.db.rpc("web_search_hit", { p_user_id: userId });
  if (allowed.data !== true) {
    return typedError(429, "daily_limit", "Daily web search limit reached");
  }

  const apiKey = deps.env("OPENAI_API_KEY");
  if (!apiKey) return typedError(503, "unavailable", "OpenAI key not configured");

  let upstream: Response;
  try {
    upstream = await deps.fetch(config.openAiUrl, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: deps.env("WEB_SEARCH_MODEL") ?? config.defaultModel,
        web_search_options: { search_context_size: "low" },
        max_completion_tokens: config.maxAnswerTokens,
        store: false,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: query },
        ],
      }),
    });
  } catch (e) {
    console.error("[web-search] fetch", e);
    return typedError(502, "upstream_failed", "Search failed");
  }
  if (!upstream.ok) {
    console.error("[web-search] upstream", upstream.status, await upstream.text());
    return typedError(502, "upstream_failed", "Search failed");
  }
  const completion = await upstream.json();
  const message = completion?.choices?.[0]?.message as Record<string, unknown> | undefined;
  const answer = typeof message?.content === "string" ? message.content.trim() : "";

  const body = answer === "" || answer.includes("FUERA_DE_TEMA")
    ? { status: answer === "" ? "empty" : "off_topic", query }
    : {
      status: "ok",
      query,
      answer,
      sources: sourcesOf(message),
      as_of: new Date(deps.now()).toISOString(),
    };
  if (body.status === "ok") {
    await deps.db.from("web_search_cache").upsert({
      query_key: key,
      body,
      fetched_at: new Date(deps.now()).toISOString(),
    });
  }
  return json(200, body, { "x-cache": "miss" });
}

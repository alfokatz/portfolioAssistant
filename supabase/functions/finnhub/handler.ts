// Proxy de Finnhub: la key vive en los secrets, solo los endpoints que usa
// la app, y una caché COMPARTIDA entre todos los usuarios (tabla
// finnhub_cache). Hoy cada dispositivo pedía lo mismo por su cuenta contra
// una key de ~60 pedidos/min para toda la app.
//
// La app llama GET /functions/v1/finnhub/<endpoint>?<params> con su JWT.

import { bearer, corsHeaders, type Deps, json, sleep, typedError } from "../_shared/common.ts";

/// Endpoints permitidos → cuánto vale la caché (mismos TTL que tenía el
/// cliente; profile2 y search cambian muy poco).
export const endpointTtlSeconds: Record<string, number> = {
  "/company-news": 10 * 60,
  "/calendar/earnings": 6 * 60 * 60,
  "/stock/earnings": 6 * 60 * 60,
  "/stock/metric": 60 * 60,
  "/stock/profile2": 24 * 60 * 60,
  "/search": 24 * 60 * 60,
};

export const config = {
  baseUrl: "https://finnhub.io/api/v1",
  /// Por usuario: un turno con 3 tickers hace ~10 pedidos, más logos.
  ratePerMinute: 120,
  /// Backoff ante 429 de Finnhub: corto, para no trabar el turno.
  retryDelaysMs: [300, 900],
};

export function cacheKey(path: string, params: URLSearchParams): string {
  const sorted = [...params.entries()]
    .filter(([k]) => k !== "token")
    .sort(([a], [b]) => a.localeCompare(b));
  return `${path}?${new URLSearchParams(sorted).toString()}`;
}

async function readCache(deps: Deps, key: string) {
  const { data } = await deps.db
    .from("finnhub_cache")
    .select("status, body, fetched_at")
    .eq("cache_key", key)
    .maybeSingle();
  return data as { status: number; body: unknown; fetched_at: string } | null;
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return typedError(405, "method_not_allowed", "GET only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  const url = new URL(req.url);
  const path = url.pathname.replace(/^.*\/finnhub/, "") || "/";
  const ttl = endpointTtlSeconds[path];
  if (ttl === undefined) return typedError(404, "endpoint_not_allowed", `${path} not allowed`);

  const allowed = await deps.db.rpc("rate_limit_hit", {
    p_user_id: userId,
    p_bucket: "finnhub",
    p_per_minute: config.ratePerMinute,
  });
  if (allowed.data === false) return typedError(429, "rate_limited", "Too many requests");

  const key = cacheKey(path, url.searchParams);
  const cached = await readCache(deps, key);
  const age = cached ? (deps.now() - Date.parse(cached.fetched_at)) / 1000 : Infinity;
  if (cached && age < ttl) {
    logCache(path, "hit");
    return json(cached.status, cached.body, { "x-cache": "hit" });
  }

  const token = deps.env("FINNHUB_API_KEY");
  if (!token) return typedError(503, "unavailable", "Finnhub key not configured");
  const upstreamUrl = new URL(config.baseUrl + path);
  for (const [k, v] of url.searchParams) if (k !== "token") upstreamUrl.searchParams.set(k, v);
  upstreamUrl.searchParams.set("token", token);

  let response: Response | null = null;
  for (let attempt = 0; ; attempt++) {
    try {
      response = await deps.fetch(upstreamUrl.toString());
    } catch {
      response = null;
    }
    const retryable = !response || response.status === 429 || response.status >= 500;
    if (!retryable || attempt >= config.retryDelaysMs.length) break;
    await response?.body?.cancel();
    await sleep(config.retryDelaysMs[attempt]);
  }

  if (!response || response.status === 429 || response.status >= 500) {
    // Sin respuesta útil: mejor un dato un poco viejo que ninguno.
    if (cached) {
      logCache(path, "stale");
      return json(cached.status, cached.body, { "x-cache": "stale" });
    }
    logCache(path, "error");
    return typedError(response?.status ?? 502, "upstream_unavailable", "Finnhub unavailable");
  }

  const text = await response.text();
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return typedError(502, "upstream_invalid", "Finnhub returned non-JSON");
  }
  if (response.status === 200) {
    const { error } = await deps.db.from("finnhub_cache").upsert({
      cache_key: key,
      status: 200,
      body,
      fetched_at: new Date(deps.now()).toISOString(),
    });
    if (error) console.error("finnhub_cache upsert failed", error.message);
  }
  logCache(path, "miss");
  return json(response.status, body, { "x-cache": "miss" });
}

/// Una línea por pedido (sin usuario ni parámetros) para medir en los logs
/// de la función cuánto evita la caché compartida: hit / (hit + miss).
function logCache(path: string, cache: "hit" | "miss" | "stale" | "error") {
  console.log(JSON.stringify({ fn: "finnhub", path, cache }));
}

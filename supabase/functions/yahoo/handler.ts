// Proxy de Yahoo Finance `quoteSummary`: composición de ETFs (topHoldings,
// fundProfile) y perfil de compañía (assetProfile, summaryDetail).
//
// Yahoo pide una cookie de sesión + un "crumb" para quoteSummary y limita
// por IP: pedirlo desde cada teléfono terminaba en 401/429 y el dato llegaba
// vacío sin aviso. Acá la sesión se arma una vez por instancia, la caché es
// COMPARTIDA entre usuarios (tabla yahoo_cache) y ante un error de Yahoo se
// sirve el último dato conocido.
//
// La app llama GET /functions/v1/yahoo/quote-summary?symbol=XLF&modules=...
// con su JWT.

import { bearer, corsHeaders, type Deps, json, sleep, typedError } from "../_shared/common.ts";

/// Módulos permitidos → cuánto vale la caché. La composición de un ETF y el
/// perfil de una compañía cambian poco; un día alcanza.
export const moduleTtlSeconds: Record<string, number> = {
  topHoldings: 24 * 60 * 60,
  fundProfile: 24 * 60 * 60,
  /// Nombre del instrumento y si es ETF, fondo o acción.
  quoteType: 24 * 60 * 60,
  assetProfile: 24 * 60 * 60,
  summaryDetail: 6 * 60 * 60,
};

export const config = {
  quoteSummaryUrl: "https://query2.finance.yahoo.com/v10/finance/quoteSummary",
  cookieUrl: "https://fc.yahoo.com",
  crumbUrl: "https://query2.finance.yahoo.com/v1/test/getcrumb",
  userAgent:
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  /// La sesión de Yahoo dura más, pero renovarla seguido evita arrastrar un
  /// crumb vencido en una instancia que vive mucho.
  sessionTtlMs: 6 * 60 * 60 * 1000,
  /// Por usuario: una simulación de inversión pide el perfil de ~10 tickers.
  ratePerMinute: 120,
  /// Backoff ante 429 de Yahoo: corto, para no trabar el turno.
  retryDelaysMs: [400, 1200],
};

const symbolPattern = /^[A-Z0-9.\-^=]{1,15}$/;

type YahooSession = { cookie: string; crumb: string; createdAt: number };

/// Una sesión por instancia de la función (no por usuario: Yahoo no sabe
/// nada del usuario, solo de la IP).
let session: YahooSession | null = null;

/// Para los tests: olvidar la sesión entre casos.
export function resetSession() {
  session = null;
}

async function getSession(deps: Deps, force = false): Promise<YahooSession | null> {
  if (!force && session && deps.now() - session.createdAt < config.sessionTtlMs) return session;
  session = null;
  try {
    const cookieRes = await deps.fetch(config.cookieUrl, {
      headers: { "User-Agent": config.userAgent },
      redirect: "manual",
    });
    // fc.yahoo.com responde 404 a propósito: lo que importa es la cookie.
    const cookie = cookieRes.headers
      .getSetCookie()
      .map((c) => c.split(";")[0])
      .filter((c) => c.includes("="))
      .join("; ");
    await cookieRes.body?.cancel();
    if (!cookie) return null;

    const crumbRes = await deps.fetch(config.crumbUrl, {
      headers: { "User-Agent": config.userAgent, Cookie: cookie },
    });
    const crumb = (await crumbRes.text()).trim();
    // Con rate limit, getcrumb devuelve 429 con el texto "Too Many Requests".
    if (crumbRes.status !== 200 || !crumb || crumb.includes(" ") || crumb.length > 64) return null;
    session = { cookie, crumb, createdAt: deps.now() };
    return session;
  } catch {
    return null;
  }
}

async function fetchQuoteSummary(
  deps: Deps,
  symbol: string,
  modules: string,
): Promise<Response | null> {
  for (let attempt = 0; ; attempt++) {
    // Un 401 es crumb vencido/rechazado: se renueva la sesión una sola vez.
    let current = await getSession(deps);
    let response = await call(deps, symbol, modules, current);
    if (response?.status === 401) {
      await response.body?.cancel();
      current = await getSession(deps, true);
      response = current ? await call(deps, symbol, modules, current) : response;
    }
    const retryable = !response || response.status === 429 || response.status >= 500;
    if (!retryable || attempt >= config.retryDelaysMs.length) return response;
    await response?.body?.cancel();
    await sleep(config.retryDelaysMs[attempt]);
  }
}

async function call(
  deps: Deps,
  symbol: string,
  modules: string,
  current: YahooSession | null,
): Promise<Response | null> {
  const url = new URL(`${config.quoteSummaryUrl}/${encodeURIComponent(symbol)}`);
  url.searchParams.set("modules", modules);
  if (current) url.searchParams.set("crumb", current.crumb);
  try {
    return await deps.fetch(url.toString(), {
      headers: {
        "User-Agent": config.userAgent,
        Accept: "application/json",
        ...(current ? { Cookie: current.cookie } : {}),
      },
    });
  } catch {
    return null;
  }
}

async function readCache(deps: Deps, key: string) {
  const { data } = await deps.db
    .from("yahoo_cache")
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
  const path = url.pathname.replace(/^.*\/yahoo/, "") || "/";
  if (path !== "/quote-summary") return typedError(404, "endpoint_not_allowed", `${path} not allowed`);

  const symbol = (url.searchParams.get("symbol") ?? "").trim().toUpperCase();
  if (!symbolPattern.test(symbol)) return typedError(400, "invalid_symbol", "Invalid symbol");
  const modules = [...new Set((url.searchParams.get("modules") ?? "").split(",").map((m) => m.trim()))]
    .filter(Boolean)
    .sort();
  if (modules.length === 0 || modules.some((m) => moduleTtlSeconds[m] === undefined)) {
    return typedError(400, "module_not_allowed", "Unknown or missing modules");
  }
  const ttl = Math.min(...modules.map((m) => moduleTtlSeconds[m]));

  const allowed = await deps.db.rpc("rate_limit_hit", {
    p_user_id: userId,
    p_bucket: "yahoo",
    p_per_minute: config.ratePerMinute,
  });
  if (allowed.data === false) return typedError(429, "rate_limited", "Too many requests");

  const key = `quote-summary?modules=${modules.join(",")}&symbol=${symbol}`;
  const cached = await readCache(deps, key);
  const age = cached ? (deps.now() - Date.parse(cached.fetched_at)) / 1000 : Infinity;
  if (cached && age < ttl) {
    log("hit");
    return json(cached.status, cached.body, { "x-cache": "hit" });
  }

  const response = await fetchQuoteSummary(deps, symbol, modules.join(","));
  if (!response || response.status === 401 || response.status === 429 || response.status >= 500) {
    await response?.body?.cancel();
    // Sin respuesta útil: mejor un dato un poco viejo que ninguno.
    if (cached) {
      log("stale");
      return json(cached.status, cached.body, { "x-cache": "stale" });
    }
    log("error", response?.status);
    return typedError(502, "upstream_unavailable", "Yahoo unavailable", {
      upstream_status: response?.status ?? null,
    });
  }

  const text = await response.text();
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return typedError(502, "upstream_invalid", "Yahoo returned non-JSON");
  }
  if (response.status === 200) {
    const { error } = await deps.db.from("yahoo_cache").upsert({
      cache_key: key,
      status: 200,
      body,
      fetched_at: new Date(deps.now()).toISOString(),
    });
    if (error) console.error("yahoo_cache upsert failed", error.message);
  }
  log("miss", response.status);
  // 404 de Yahoo (símbolo inexistente) pasa tal cual: la app lo lee como
  // "sin datos", no como falla.
  return json(response.status, body, { "x-cache": "miss" });
}

/// Una línea por pedido (sin usuario ni símbolo) para medir en los logs
/// cuánto evita la caché y si Yahoo empieza a bloquear la IP del servidor.
function log(cache: "hit" | "miss" | "stale" | "error", upstream?: number) {
  console.log(JSON.stringify({ fn: "yahoo", cache, upstream: upstream ?? null }));
}

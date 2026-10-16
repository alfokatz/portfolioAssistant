// binance-sync: conecta la cuenta de Binance del usuario con una clave de
// API de SOLO LECTURA y replica sus saldos en Porty (F6 de
// docs/superpowers/plans/2026-10-16-porty-siguiente-nivel.md).
//
// Rutas (todas bajo /functions/v1/binance-sync, con JWT):
//   POST /connect     { api_key, api_secret } → { result }
//   POST /sync        → { result, throttled }
//   POST /disconnect  { keepAsManual } → { open, keptAsManual }
//
// La clave nunca vuelve a la app ni va a los logs. Se rechaza cualquier
// clave que pueda operar, retirar o transferir.

import { bearer, corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { BinanceClient, binanceConfig, BinanceError } from "./binance.ts";
import { keyProblem } from "./mapping.ts";
import { type BinanceStore, supabaseStore } from "./store.ts";
import { runSync, type SyncErrorType } from "./sync.ts";

export const handlerConfig = {
  ratePerMinute: 12,
  allowedTiers: ["premium", "gold"],
  keyPattern: /^[A-Za-z0-9]{16,128}$/,
};

const syncErrorStatus: Record<SyncErrorType, number> = {
  binance_not_connected: 409,
  binance_reconnect_required: 409,
  binance_sync_in_progress: 409,
  binance_rate_limited: 429,
  binance_region_blocked: 503,
  binance_unavailable: 503,
};

function log(fields: Record<string, unknown>) {
  // Nunca claves ni ids de usuario: solo qué pasó.
  console.log(JSON.stringify({ fn: "binance-sync", ...fields }));
}

export async function handle(
  req: Request,
  deps: Deps,
  storeFor: (deps: Deps) => BinanceStore = (d) => supabaseStore(d.db),
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  const store = storeFor(deps);
  if (!(await store.rateLimitHit(userId, handlerConfig.ratePerMinute))) {
    return typedError(429, "rate_limited", "Too many requests");
  }
  const client = new BinanceClient(deps.fetch, deps.now, deps.env("BINANCE_API_URL") || binanceConfig.defaultBaseUrl);
  const route = new URL(req.url).pathname.replace(/^.*\/binance-sync/, "") || "/";

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    // sin body
  }

  switch (route) {
    case "/connect":
      return await connect(userId, body, store, client, deps);
    case "/sync":
      return await sync(userId, store, client, deps);
    case "/disconnect":
      return await disconnect(userId, body, store);
    default:
      return typedError(404, "not_found", `${route} not found`);
  }
}

async function planAllows(store: BinanceStore, userId: string): Promise<boolean> {
  return handlerConfig.allowedTiers.includes(await store.effectiveTier(userId));
}

async function connect(
  userId: string,
  body: Record<string, unknown>,
  store: BinanceStore,
  client: BinanceClient,
  deps: Deps,
) {
  if (!(await planAllows(store, userId))) {
    return typedError(403, "binance_plan_required", "Binance sync requires Premium or Gold");
  }
  const apiKey = typeof body.api_key === "string" ? body.api_key.trim() : "";
  const apiSecret = typeof body.api_secret === "string" ? body.api_secret.trim() : "";
  if (!handlerConfig.keyPattern.test(apiKey) || !handlerConfig.keyPattern.test(apiSecret)) {
    return typedError(400, "binance_invalid_key", "api_key and api_secret look invalid");
  }
  const keys = { apiKey, apiSecret };

  // Antes de guardar nada: la clave tiene que ser de solo lectura.
  try {
    const problem = keyProblem(await client.apiRestrictions(keys));
    if (problem) {
      log({ op: "connect", outcome: problem });
      return typedError(
        422,
        problem === "write_permissions" ? "binance_write_permissions" : "binance_no_read",
        problem,
      );
    }
  } catch (e) {
    const type = e instanceof BinanceError ? e.type : "unavailable";
    log({ op: "connect", outcome: type });
    const [status, error] = type === "invalid_key"
      ? [400, "binance_invalid_key"]
      : type === "region_blocked"
      ? [503, "binance_region_blocked"]
      : type === "rate_limited"
      ? [429, "binance_rate_limited"]
      : [503, "binance_unavailable"];
    return typedError(status as number, error as string, "Could not verify the API key");
  }

  await store.saveKeys(userId, keys);
  await store.upsertConnected(userId, apiKey.slice(-4));
  const outcome = await runSync({ userId, store, client, now: deps.now, force: true });
  log({ op: "connect", outcome: outcome.ok ? "connected" : `connected_sync_${outcome.error}` });
  if (outcome.ok) return json(200, { result: outcome.result });
  // Conectada pero la primera importación falló (se reintenta al abrir).
  return json(200, { result: null, syncError: outcome.error });
}

async function sync(userId: string, store: BinanceStore, client: BinanceClient, deps: Deps) {
  if (!(await planAllows(store, userId))) {
    return typedError(403, "binance_plan_required", "Binance sync requires Premium or Gold");
  }
  const outcome = await runSync({ userId, store, client, now: deps.now });
  log({ op: "sync", outcome: outcome.ok ? (outcome.throttled ? "throttled" : "ok") : outcome.error });
  if (outcome.ok) return json(200, { result: outcome.result, throttled: outcome.throttled });
  return typedError(syncErrorStatus[outcome.error], outcome.error, "Binance sync failed");
}

async function disconnect(userId: string, body: Record<string, unknown>, store: BinanceStore) {
  const keepAsManual = body.keepAsManual;
  if (typeof keepAsManual !== "boolean") {
    return typedError(400, "invalid_request", "keepAsManual (boolean) is required");
  }
  const removed = await store.disconnect(userId, keepAsManual);
  log({ op: "disconnect", keepAsManual });
  return json(200, { ...removed, keptAsManual: keepAsManual });
}

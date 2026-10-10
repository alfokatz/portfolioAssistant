// etoro-sync: conecta la cuenta de eToro del usuario (OAuth, SOLO LECTURA) y
// replica su portfolio en Porty.
//
// Rutas (todas bajo /functions/v1/etoro-sync):
//   POST /connect/start   JWT  → { authorizeUrl } para abrir en el navegador
//   GET  /callback        —    eToro vuelve acá; 302 al deep link de la app
//   POST /sync            JWT  → { result, throttled }
//   POST /disconnect      JWT  { keepAsManual } → { open, closed }
//
// Los tokens de eToro nunca salen de acá: ni a la app ni a los logs. El
// deep link de vuelta solo lleva un estado (`ok`, `cancelled`…).

import { bearer, corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import {
  codeChallengeS256,
  EtoroClient,
  type EtoroEnvironment,
  etoroEnvironment,
  EtoroError,
  randomToken,
  readScope,
  requestedScopes,
  writeScopes,
} from "./etoro.ts";
import { type EtoroStore, supabaseStore } from "./store.ts";
import { runSync, type SyncErrorType } from "./sync.ts";

export const handlerConfig = {
  /// Pedidos a esta función por usuario y minuto (start + sync + disconnect).
  ratePerMinute: 12,
  /// Vida de un intento de conexión (state/PKCE).
  stateTtlMs: 10 * 60 * 1000,
  defaultAppRedirect: "porty-etoro://callback",
  allowedTiers: ["premium", "gold"],
};

const syncErrorStatus: Record<SyncErrorType, number> = {
  etoro_not_connected: 409,
  etoro_reconnect_required: 409,
  etoro_sync_in_progress: 409,
  etoro_rate_limited: 429,
  etoro_unavailable: 503,
  etoro_forbidden: 502,
  etoro_sync_failed: 502,
};

type Env = {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  appRedirect: string;
  environment: EtoroEnvironment;
};

function readEnv(deps: Deps): Env | null {
  const clientId = deps.env("ETORO_CLIENT_ID");
  const clientSecret = deps.env("ETORO_CLIENT_SECRET");
  const redirectUri = deps.env("ETORO_REDIRECT_URI");
  if (!clientId || !clientSecret || !redirectUri) return null;
  return {
    clientId,
    clientSecret,
    redirectUri,
    appRedirect: deps.env("ETORO_APP_REDIRECT") ?? handlerConfig.defaultAppRedirect,
    // Solo staging: "demo" para probar con una cuenta de dinero virtual.
    environment: etoroEnvironment(deps.env("ETORO_ENVIRONMENT")),
  };
}

function log(fields: Record<string, unknown>) {
  // Nunca tokens, códigos ni ids de usuario: solo qué pasó.
  console.log(JSON.stringify({ fn: "etoro-sync", ...fields }));
}

function appRedirect(env: Env, status: string, reason?: string): Response {
  const url = new URL(env.appRedirect);
  url.searchParams.set("status", status);
  if (reason) url.searchParams.set("reason", reason);
  return new Response(null, {
    status: 302,
    headers: { Location: url.toString(), "Cache-Control": "no-store" },
  });
}

export async function handle(
  req: Request,
  deps: Deps,
  storeFor: (deps: Deps) => EtoroStore = (d) => supabaseStore(d.db),
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const env = readEnv(deps);
  if (!env) return typedError(503, "etoro_not_configured", "eToro OAuth client not configured");

  const store = storeFor(deps);
  const client = new EtoroClient(deps.fetch, env, deps.now, env.environment);
  const route = new URL(req.url).pathname.replace(/^.*\/etoro-sync/, "") || "/";

  if (route === "/callback" && req.method === "GET") return await callback(req, env, store, client, deps);

  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");
  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");
  if (!(await store.rateLimitHit(userId, handlerConfig.ratePerMinute))) {
    return typedError(429, "rate_limited", "Too many requests");
  }

  switch (route) {
    case "/connect/start":
      return await connectStart(userId, store, client, deps);
    case "/sync":
      return await sync(userId, store, client, deps);
    case "/disconnect":
      return await disconnect(req, userId, store, client);
    default:
      return typedError(404, "not_found", `${route} not found`);
  }
}

async function planAllows(store: EtoroStore, userId: string): Promise<boolean> {
  return handlerConfig.allowedTiers.includes(await store.effectiveTier(userId));
}

async function connectStart(userId: string, store: EtoroStore, client: EtoroClient, deps: Deps) {
  if (!(await planAllows(store, userId))) {
    return typedError(403, "etoro_plan_required", "eToro sync requires Premium or Gold");
  }
  const state = randomToken(24);
  const nonce = randomToken(24);
  const codeVerifier = randomToken(48);
  await store.saveOAuthState({
    state,
    userId,
    codeVerifier,
    nonce,
    createdAt: new Date(deps.now()).toISOString(),
  });
  const authorizeUrl = await client.authorizeUrl({
    state,
    nonce,
    codeChallenge: await codeChallengeS256(codeVerifier),
  });
  log({ op: "connect_start" });
  return json(200, { authorizeUrl });
}

async function callback(req: Request, env: Env, store: EtoroStore, client: EtoroClient, deps: Deps) {
  const params = new URL(req.url).searchParams;
  const stateParam = params.get("state");
  if (!stateParam) return appRedirect(env, "error", "invalid_state");

  // Un solo uso: se borra al leerlo, salga bien o mal.
  const state = await store.takeOAuthState(stateParam);
  if (!state || deps.now() - Date.parse(state.createdAt) > handlerConfig.stateTtlMs) {
    log({ op: "callback", outcome: "invalid_state" });
    return appRedirect(env, "error", "expired");
  }

  // El usuario canceló o eToro rechazó la autorización.
  if (params.get("error")) {
    log({ op: "callback", outcome: "denied" });
    return appRedirect(env, "cancelled");
  }
  const code = params.get("code");
  if (!code) return appRedirect(env, "error", "invalid_response");

  if (!(await planAllows(store, state.userId))) return appRedirect(env, "error", "plan_required");

  try {
    const { tokens, idToken } = await client.exchangeCode(code, state.codeVerifier);

    // Solo lectura, sin excepciones: si eToro concedió algo que permita
    // operar, se revoca todo y no se guarda nada.
    const granted = tokens.scope.length > 0 ? tokens.scope : requestedScopes(env.environment);
    if (writeScopes(granted).length > 0 || !granted.includes(readScope(env.environment))) {
      if (tokens.refreshToken) await client.revoke(tokens.refreshToken, "refresh_token");
      await client.revoke(tokens.accessToken, "access_token");
      const reason = writeScopes(granted).length > 0 ? "write_scope" : "missing_scope";
      log({ op: "callback", outcome: reason });
      return appRedirect(env, "error", reason);
    }

    if (!idToken) return appRedirect(env, "error", "invalid_response");
    const sub = await client.verifyIdToken(idToken, state.nonce);

    // Otra cuenta de eToro que la conectada antes: lo importado de la
    // anterior se borra (no se mezclan carteras).
    const previous = await store.getConnection(state.userId);
    if (previous?.etoroSub && previous.etoroSub !== sub && previous.status !== "disconnected") {
      await store.disconnect(state.userId, false);
    }

    await store.saveTokens(state.userId, tokens);
    await store.upsertConnected(state.userId, sub, granted);

    const outcome = await runSync({ userId: state.userId, store, client, now: deps.now, force: true });
    log({ op: "callback", outcome: outcome.ok ? "connected" : `connected_sync_${outcome.error}` });
    return outcome.ok ? appRedirect(env, "ok") : appRedirect(env, "sync_error", outcome.error);
  } catch (e) {
    const reason = e instanceof EtoroError ? e.type : "unexpected";
    log({ op: "callback", outcome: "failed", reason });
    return appRedirect(env, "error", reason === "config" ? "unavailable" : "failed");
  }
}

async function sync(userId: string, store: EtoroStore, client: EtoroClient, deps: Deps) {
  if (!(await planAllows(store, userId))) {
    return typedError(403, "etoro_plan_required", "eToro sync requires Premium or Gold");
  }
  const started = deps.now();
  const outcome = await runSync({ userId, store, client, now: deps.now });
  log({
    op: "sync",
    outcome: outcome.ok ? (outcome.throttled ? "throttled" : "ok") : outcome.error,
    ms: deps.now() - started,
  });
  if (outcome.ok) return json(200, { result: outcome.result, throttled: outcome.throttled });
  return typedError(
    syncErrorStatus[outcome.error],
    outcome.error,
    "eToro sync failed",
    outcome.retryAfterSeconds ? { retryAfterSeconds: outcome.retryAfterSeconds } : {},
  );
}

async function disconnect(req: Request, userId: string, store: EtoroStore, client: EtoroClient) {
  let keepAsManual: unknown;
  try {
    keepAsManual = (await req.json())?.keepAsManual;
  } catch {
    keepAsManual = undefined;
  }
  if (typeof keepAsManual !== "boolean") {
    return typedError(400, "invalid_request", "keepAsManual (boolean) is required");
  }
  // Revocar en eToro primero (si falla, igual se borra todo de nuestro lado).
  const tokens = await store.readTokens(userId).catch(() => null);
  let revoked = false;
  if (tokens?.refreshToken) revoked = await client.revoke(tokens.refreshToken, "refresh_token");
  if (tokens?.accessToken) await client.revoke(tokens.accessToken, "access_token");
  const removed = await store.disconnect(userId, keepAsManual);
  log({ op: "disconnect", keepAsManual, revoked });
  return json(200, { ...removed, keptAsManual: keepAsManual, revoked });
}

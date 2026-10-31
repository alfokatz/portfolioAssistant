// snaptrade-sync: conecta brókers del usuario por SnapTrade, de SOLO
// LECTURA, y replica sus posiciones en Porty. Para los brókers que Porty no
// conecta directo (IBKR, Schwab…). Ver docs/runbooks/snaptrade-sync.md.
//
// Rutas (todas bajo /functions/v1/snaptrade-sync, con JWT):
//   POST /connect     { darkMode?, reconnect? } → { portalUrl }
//   POST /sync        { force? } → { result, throttled }  (force: al volver del portal)
//   POST /refresh     → { queued }  (Gold, si está habilitado)
//   POST /remove      { authorizationId } → { result }
//   POST /disconnect  { keepAsManual } → { open, keptAsManual }
//
// Planes: Premium conecta un bróker; Gold, todos, y puede pedir
// "Actualizar ahora" (SnapTrade cobra cada una: se habilita con
// SNAPTRADE_MANUAL_REFRESH=on y tiene cupo diario).
//
// El secreto del usuario de SnapTrade nunca vuelve a la app ni va a los
// logs. El portal se abre siempre con `connectionType = read`.

import { bearer, corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { countedBrokerages, planConfig, selectBrokerages } from "./mapping.ts";
import { SnaptradeClient, snaptradeConfig, SnaptradeError } from "./snaptrade.ts";
import { type SnaptradeStore, supabaseStore } from "./store.ts";
import { runSync, type SyncErrorType } from "./sync.ts";

export const handlerConfig = {
  ratePerMinute: 12,
  defaultAppRedirect: "porty-snaptrade://callback",
  /// Actualizaciones manuales por usuario y día (cada una se paga).
  defaultRefreshPerDay: 2,
};

const syncErrorStatus: Record<SyncErrorType, number> = {
  snaptrade_not_connected: 409,
  snaptrade_reconnect_required: 409,
  snaptrade_sync_in_progress: 409,
  snaptrade_rate_limited: 429,
  snaptrade_unavailable: 503,
};

function log(fields: Record<string, unknown>) {
  // Nunca secretos ni ids de usuario: solo qué pasó.
  console.log(JSON.stringify({ fn: "snaptrade-sync", ...fields }));
}

type Ctx = {
  userId: string;
  tier: string;
  store: SnaptradeStore;
  client: SnaptradeClient;
  deps: Deps;
};

export async function handle(
  req: Request,
  deps: Deps,
  storeFor: (deps: Deps) => SnaptradeStore = (d) => supabaseStore(d.db),
  newId: () => string = () => crypto.randomUUID(),
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  const clientId = deps.env("SNAPTRADE_CLIENT_ID");
  const consumerKey = deps.env("SNAPTRADE_CONSUMER_KEY");
  if (!clientId || !consumerKey) {
    return typedError(503, "snaptrade_not_configured", "SnapTrade is not configured");
  }

  const store = storeFor(deps);
  if (!(await store.rateLimitHit(userId, handlerConfig.ratePerMinute))) {
    return typedError(429, "rate_limited", "Too many requests");
  }
  const tier = await store.effectiveTier(userId);
  const client = new SnaptradeClient(
    deps.fetch,
    deps.now,
    { clientId, consumerKey },
    deps.env("SNAPTRADE_API_URL") || snaptradeConfig.defaultBaseUrl,
  );
  const ctx: Ctx = { userId, tier, store, client, deps };
  const route = new URL(req.url).pathname.replace(/^.*\/snaptrade-sync/, "") || "/";

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    // sin body
  }

  // Desconectar siempre se puede (también después de bajar a Free: así deja
  // de cobrarse).
  if (route !== "/disconnect" && !planConfig[tier]) {
    return typedError(403, "snaptrade_plan_required", "SnapTrade requires Premium or Gold");
  }

  try {
    switch (route) {
      case "/connect":
        return await connect(ctx, body, newId);
      case "/sync":
        return await sync(ctx, body.force === true);
      case "/refresh":
        return await refresh(ctx);
      case "/remove":
        return await remove(ctx, body);
      case "/disconnect":
        return await disconnect(ctx, body);
      default:
        return typedError(404, "not_found", `${route} not found`);
    }
  } catch (e) {
    if (!(e instanceof SnaptradeError)) throw e;
    log({ op: route, outcome: e.type });
    return e.type === "rate_limited"
      ? typedError(429, "snaptrade_rate_limited", "SnapTrade rate limit")
      : typedError(503, "snaptrade_unavailable", "SnapTrade request failed");
  }
}

/// La URL del Connection Portal. La primera vez (o si hay que reconectar)
/// crea el usuario en SnapTrade.
async function connect(ctx: Ctx, body: Record<string, unknown>, newId: () => string) {
  const { userId, store, client, deps } = ctx;
  const reconnect = typeof body.reconnect === "string" && body.reconnect ? body.reconnect : undefined;
  const connection = await store.getConnection(userId);
  let user = await store.readUser(userId);
  const fresh = !user || connection?.status === "reconnect_required";
  if (fresh) {
    // El usuario viejo de SnapTrade (si quedó) se borra: no se paga por él.
    if (user) await client.deleteUser(user.userId).catch(() => {});
    // Un id propio al azar: SnapTrade nunca ve el id de Porty.
    user = await client.registerUser(newId());
    await store.saveUser(userId, user);
  }
  const max = planConfig[ctx.tier].maxBrokerages;
  if (!fresh && !reconnect && max !== null && countedBrokerages(await client.authorizations(user!)) >= max) {
    log({ op: "connect", outcome: "connection_limit" });
    return typedError(409, "snaptrade_connection_limit", "The plan allows one brokerage");
  }
  await store.upsertPending(userId, fresh);
  const portalUrl = await client.portalUrl(user!, {
    redirect: deps.env("SNAPTRADE_APP_REDIRECT") ?? handlerConfig.defaultAppRedirect,
    darkMode: body.darkMode === true,
    reconnect: fresh ? undefined : reconnect,
  });
  log({ op: "connect", outcome: fresh ? "registered" : "portal" });
  return json(200, { portalUrl });
}

async function sync(ctx: Ctx, force: boolean) {
  const outcome = await runSync({
    userId: ctx.userId,
    store: ctx.store,
    client: ctx.client,
    now: ctx.deps.now,
    maxBrokerages: planConfig[ctx.tier].maxBrokerages,
    force,
  });
  log({ op: "sync", outcome: outcome.ok ? (outcome.throttled ? "throttled" : "ok") : outcome.error });
  if (outcome.ok) return json(200, { result: outcome.result, throttled: outcome.throttled });
  return typedError(syncErrorStatus[outcome.error], outcome.error, "SnapTrade sync failed");
}

/// "Actualizar ahora": SnapTrade vuelve a leer el bróker en segundo plano.
/// Lo nuevo aparece en la próxima sincronización.
async function refresh(ctx: Ctx) {
  const { userId, store, client, deps } = ctx;
  if (!planConfig[ctx.tier].manualRefresh) {
    return typedError(403, "snaptrade_refresh_plan_required", "Manual refresh requires Gold");
  }
  if (deps.env("SNAPTRADE_MANUAL_REFRESH") !== "on") {
    return typedError(403, "snaptrade_refresh_unavailable", "Manual refresh is off");
  }
  const user = await store.readUser(userId);
  if (!user) return typedError(409, "snaptrade_not_connected", "Not connected");
  const targets = selectBrokerages(await client.authorizations(user), planConfig[ctx.tier].maxBrokerages)
    .filter((b) => b.imported && !b.disabled);
  if (targets.length === 0) return json(200, { queued: 0 });
  const perDay = Number(deps.env("SNAPTRADE_REFRESH_PER_DAY")) || handlerConfig.defaultRefreshPerDay;
  if (!(await store.takeRefresh(userId, perDay))) {
    return typedError(429, "snaptrade_refresh_limit", "Daily manual refresh limit reached");
  }
  for (const b of targets) await client.refreshAuthorization(user, b.id);
  log({ op: "refresh", queued: targets.length });
  return json(200, { queued: targets.length });
}

/// Quita un bróker (por ejemplo, para cambiarlo por otro en Premium).
async function remove(ctx: Ctx, body: Record<string, unknown>) {
  const authorizationId = typeof body.authorizationId === "string" ? body.authorizationId : "";
  if (!/^[A-Za-z0-9-]{8,64}$/.test(authorizationId)) {
    return typedError(400, "invalid_request", "authorizationId is required");
  }
  const user = await ctx.store.readUser(ctx.userId);
  if (!user) return typedError(409, "snaptrade_not_connected", "Not connected");
  await ctx.client.deleteAuthorization(user, authorizationId);
  log({ op: "remove" });
  return await sync(ctx, true);
}

/// Borra el usuario en SnapTrade (deja de cobrarse) y, en Porty, el secreto
/// y lo importado (o lo deja como manual).
async function disconnect(ctx: Ctx, body: Record<string, unknown>) {
  const keepAsManual = body.keepAsManual;
  if (typeof keepAsManual !== "boolean") {
    return typedError(400, "invalid_request", "keepAsManual (boolean) is required");
  }
  const user = await ctx.store.readUser(ctx.userId);
  // Si SnapTrade no responde, no se desconecta: seguiría cobrándose.
  if (user) await ctx.client.deleteUser(user.userId);
  const removed = await ctx.store.disconnect(ctx.userId, keepAsManual);
  log({ op: "disconnect", keepAsManual });
  return json(200, { ...removed, keptAsManual: keepAsManual });
}

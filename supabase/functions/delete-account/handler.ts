// Borrado de cuenta desde la app (spec docs/superpowers/specs/2026-11-02-borrado-de-cuenta.md §3.3).
//
// Pasos, en orden; cada uno es un no-op si ya estaba hecho, así que la
// función es idempotente y se puede reintentar después de un corte:
//   0. JWT → uid (antes de todo: un 401 garantiza que no se tocó nada),
//      `confirm: true`, rate limit y chequeo de configuración.
//   1. SnapTrade: borra el usuario allá (deja de cobrarse) y el secreto acá.
//   2. RevenueCat: DELETE /subscribers/{uid}.
//   3. eToro: revoca los tokens (best effort) y desconecta.
//   4. Binance: desconecta (borra la clave de Vault; Binance no tiene API de
//      revocación y la clave es de solo lectura).
//   5. auth.admin.deleteUser: dispara el trigger
//      `account_purge_before_delete` y todos los cascades.
//   6. Segundo DELETE en RevenueCat (best effort, nunca cambia el 200).
//
// Los *_disconnect van con keep_as_manual: si un paso posterior falla, la
// cartera queda entera como manual. Al final el cascade la borra igual.
//
// Errores: siempre `{error: {type, message, step?, nothingDeleted}}`.
// `nothingDeleted` es false si ESTA llamada ya hizo alguna mutación; la app
// elige el texto con eso.
//
// SnaptradeClient y EtoroClient se importan sin editar: un cambio en
// snaptrade-sync/snaptrade.ts, etoro-sync/etoro.ts o revenuecat-webhook/
// handler.ts obliga a redesplegar también esta función.

import { bearer, corsHeaders, type Deps, json, sleep, typedError } from "../_shared/common.ts";
import { EtoroClient, etoroEnvironment, type EtoroTokens } from "../etoro-sync/etoro.ts";
import { config as revenueCatConfig } from "../revenuecat-webhook/handler.ts";
import { SnaptradeClient, SnaptradeError, snaptradeConfig } from "../snaptrade-sync/snaptrade.ts";

export const config = {
  rateBucket: "delete_account",
  ratePerMinute: 5,
  /// Tope por pedido externo y presupuesto total del lado del servidor (la
  /// app espera 60 s).
  requestTimeoutMs: 10_000,
  budgetMs: 40_000,
  recheckTimeoutMs: 5_000,
};

type Step = "snaptrade" | "revenuecat" | "etoro" | "binance" | "auth";

function log(fields: Record<string, unknown>) {
  // Nunca el uid ni tokens: solo qué pasó.
  console.log(JSON.stringify({ fn: "delete-account", op: "delete", ...fields }));
}

function fail(status: number, type: string, message: string, nothingDeleted: boolean, step?: Step): Response {
  if (step) log({ step, outcome: type });
  return typedError(status, type, message, { ...(step ? { step } : {}), nothingDeleted });
}

/// `fetch` con timeout por pedido y un límite total: la función no puede
/// pasarse del presupuesto aunque los proveedores no respondan.
function boundedFetch(deps: Deps, deadline: number): typeof fetch {
  return (input, init) => {
    const left = deadline - Date.now();
    if (left <= 0) return Promise.reject(new Error("deadline"));
    const timeout = AbortSignal.timeout(Math.min(config.requestTimeoutMs, left));
    const signal = init?.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
    return deps.fetch(input, { ...init, signal });
  };
}

const isNotFound = (error: { status?: number; code?: string } | null | undefined) =>
  error?.status === 404 || error?.code === "user_not_found";

/// DELETE del cliente en RevenueCat. 200 y 404 son ok; 5xx, 429 o red se
/// reintentan como en el webhook.
async function deleteRevenueCatCustomer(fetchFn: typeof fetch, key: string, userId: string): Promise<"deleted" | "absent" | "failed"> {
  for (let attempt = 0; ; attempt++) {
    try {
      const response = await fetchFn(`${revenueCatConfig.apiBase}/subscribers/${encodeURIComponent(userId)}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${key}`, Accept: "application/json" },
      });
      await response.body?.cancel();
      if (response.ok) return "deleted";
      if (response.status === 404) return "absent";
      if (response.status < 500 && response.status !== 429) return "failed";
    } catch {
      // Red o timeout: se reintenta.
    }
    if (attempt >= revenueCatConfig.retryDelaysMs.length) return "failed";
    await sleep(revenueCatConfig.retryDelaysMs[attempt]);
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail(405, "method_not_allowed", "POST only", true);

  // 0. Sesión primero (compliance §6.1).
  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return fail(401, "unauthorized", "Missing or invalid JWT", true);

  let body: Record<string, unknown> | null = null;
  try {
    body = await req.json();
  } catch {
    body = null;
  }
  if (body?.confirm !== true) return fail(400, "invalid_request", "confirm: true is required", true);

  const rate = await deps.db.rpc("rate_limit_hit", {
    p_user_id: userId,
    p_bucket: config.rateBucket,
    p_per_minute: config.ratePerMinute,
  });
  if (rate.error?.code === "23503") {
    // El uid ya no está en auth.users: un borrado anterior terminó y se perdió
    // la respuesta (con JWT asimétrico el token viejo sigue validando).
    log({ step: "auth", outcome: "already_deleted" });
    return json(200, { deleted: true });
  }
  if (rate.error) return fail(500, "delete_failed", "Could not start the deletion", true);
  if (rate.data !== true) return fail(429, "rate_limited", "Too many requests", true);

  const revenueCatKey = deps.env("REVENUECAT_SECRET_API_KEY");
  if (!revenueCatKey) return fail(500, "misconfigured", "Account deletion is not configured", true);

  const snap = await deps.db.rpc("snaptrade_secret_read", { p_user_id: userId });
  if (snap.error) return fail(502, "upstream_unavailable", "Could not read the SnapTrade user", true, "snaptrade");
  const snapSecret = typeof snap.data === "string" ? snap.data : null;
  const snapClientId = deps.env("SNAPTRADE_CLIENT_ID");
  const snapConsumerKey = deps.env("SNAPTRADE_CONSUMER_KEY");
  if (snapSecret && (!snapClientId || !snapConsumerKey)) {
    return fail(500, "misconfigured", "Account deletion is not configured", true);
  }

  const fetchFn = boundedFetch(deps, Date.now() + config.budgetMs);
  let mutated = false;

  // 1. SnapTrade.
  if (snapSecret) {
    let snapUserId: string | null = null;
    try {
      const parsed = JSON.parse(snapSecret);
      snapUserId = typeof parsed?.user_id === "string" && parsed.user_id ? parsed.user_id : null;
    } catch {
      snapUserId = null;
    }
    if (snapUserId) {
      const client = new SnaptradeClient(
        fetchFn,
        deps.now,
        { clientId: snapClientId!, consumerKey: snapConsumerKey! },
        deps.env("SNAPTRADE_API_URL") || snaptradeConfig.defaultBaseUrl,
      );
      try {
        await client.deleteUser(snapUserId); // 404 = ya no existía: ok.
      } catch (e) {
        log({ step: "snaptrade", outcome: "upstream_error", type: e instanceof SnaptradeError ? e.type : "network" });
        return fail(502, "upstream_unavailable", "SnapTrade unavailable", !mutated, "snaptrade");
      }
      mutated = true;
    } else {
      // Sin id legible no se puede borrar allá; se borra nuestra copia igual
      // para que el borrado no quede trabado para siempre.
      log({ step: "snaptrade", outcome: "secret_unreadable" });
    }
    const { error } = await deps.db.rpc("snaptrade_disconnect", { p_user_id: userId, p_keep_as_manual: true });
    if (error) return fail(502, "upstream_unavailable", "Could not disconnect SnapTrade", !mutated, "snaptrade");
    mutated = true;
  }

  // 2. RevenueCat.
  const revenueCat = await deleteRevenueCatCustomer(fetchFn, revenueCatKey, userId);
  if (revenueCat === "failed") {
    return fail(502, "upstream_unavailable", "RevenueCat unavailable", !mutated, "revenuecat");
  }
  if (revenueCat === "deleted") mutated = true;

  // 3. eToro: revocar es best effort y nunca corta; solo un error de DB corta.
  const etoro = await deps.db.rpc("etoro_tokens_read", { p_user_id: userId });
  if (etoro.error) return fail(500, "delete_failed", "Could not disconnect eToro", !mutated, "etoro");
  if (typeof etoro.data === "string") {
    let tokens: Partial<EtoroTokens> | null = null;
    try {
      tokens = JSON.parse(etoro.data);
    } catch {
      tokens = null;
    }
    const clientId = deps.env("ETORO_CLIENT_ID");
    const clientSecret = deps.env("ETORO_CLIENT_SECRET");
    let revoked = false;
    if (tokens && clientId && clientSecret) {
      const client = new EtoroClient(
        fetchFn,
        { clientId, clientSecret, redirectUri: deps.env("ETORO_REDIRECT_URI") ?? "" },
        deps.now,
        etoroEnvironment(deps.env),
      );
      if (typeof tokens.refreshToken === "string") revoked = await client.revoke(tokens.refreshToken, "refresh_token");
      if (typeof tokens.accessToken === "string") await client.revoke(tokens.accessToken, "access_token");
    }
    log({ step: "etoro", outcome: revoked ? "revoked" : "not_revoked" });
  }
  const etoroDisconnect = await deps.db.rpc("etoro_disconnect", { p_user_id: userId, p_keep_as_manual: true });
  if (etoroDisconnect.error) return fail(500, "delete_failed", "Could not disconnect eToro", !mutated, "etoro");
  mutated = true;

  // 4. Binance.
  const binance = await deps.db.rpc("binance_disconnect", { p_user_id: userId, p_keep_as_manual: true });
  if (binance.error) return fail(500, "delete_failed", "Could not disconnect Binance", !mutated, "binance");

  // 5. Auth: borrado duro. Si ya no existe, cuenta como hecho.
  const deleted = await deps.db.auth.admin.deleteUser(userId);
  if (deleted.error && !isNotFound(deleted.error as { status?: number; code?: string })) {
    return fail(500, "delete_failed", "Could not delete the account", !mutated, "auth");
  }

  log({ step: "auth", outcome: "deleted" });

  // 6. Segundo DELETE en RevenueCat, best effort y sin reintentos: un evento
  //    que llegó entre el paso 2 y el 5 pudo recrear al cliente con el GET del
  //    webhook. Desde el paso 5 el webhook ya no llama a RevenueCat para este
  //    uid, así que esto cierra la ventana. Si falla, la respuesta sigue en 200.
  try {
    // Timeout propio: si los pasos anteriores agotaron el presupuesto de
    // fetchFn, este paso igual tiene que correr.
    const response = await deps.fetch(`${revenueCatConfig.apiBase}/subscribers/${encodeURIComponent(userId)}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${revenueCatKey}`, Accept: "application/json" },
      signal: AbortSignal.timeout(config.recheckTimeoutMs),
    });
    await response.body?.cancel();
    if (!response.ok && response.status !== 404) log({ step: "revenuecat", outcome: "revenuecat_recheck_failed" });
  } catch {
    log({ step: "revenuecat", outcome: "revenuecat_recheck_failed" });
  }

  return json(200, { deleted: true });
}

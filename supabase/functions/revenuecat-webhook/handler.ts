// Webhook de RevenueCat → user_subscriptions.
//
// El evento solo dice A QUIÉN recalcular. El plan sale del estado ACTUAL del
// usuario en RevenueCat (GET /v1/subscribers/{id}): el entitlement activo más
// alto (gold > premium), incluidos los promocionales. Por eso es idempotente
// y no depende del orden en que lleguen los eventos (RevenueCat reintenta y
// puede desordenar).
//
// Antes: el plan salía del product_id del evento y EXPIRATION forzaba Free,
// aunque el usuario tuviera otra suscripción activa (p. ej. vence una promo
// Gold de alguien que paga Premium → quedaba en Free). Y CANCELLATION ponía
// status 'canceled', que la cuota trata como Free aunque quedara período.
//
// Si RevenueCat no responde, no se toca nada: 503 para que RevenueCat
// reintente, y queda registrado en subscription_sync_log.
//
// Además, cada evento queda en subscription_events (precio, tienda, trial,
// entorno, paywall_source) ANTES de recalcular el plan, idempotente por
// event.id. Si guardarlo falla, el plan se recalcula igual (la analítica
// nunca traba un plan) y se responde 500 para que RevenueCat reintente.

import { corsHeaders, type Deps, json, sleep, typedError } from "../_shared/common.ts";

export const config = {
  apiBase: "https://api.revenuecat.com/v1",
  retryDelaysMs: [400, 1200],
  /// Orden de preferencia: el primero activo gana.
  tiers: ["gold", "premium"] as const,
};

type Entitlement = {
  expires_date?: string | null;
  grace_period_expires_date?: string | null;
  product_identifier?: string;
};

type Subscriber = { entitlements?: Record<string, Entitlement> };

const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// Los ids de la app (Supabase auth) que este evento toca. Los anónimos de
/// RevenueCat ($RCAnonymousID:...) no tienen fila propia: se ignoran.
export function affectedUserIds(event: Record<string, unknown>): string[] {
  const ids = new Set<string>();
  const add = (v: unknown) => {
    if (typeof v === "string" && uuidRe.test(v)) ids.add(v.toLowerCase());
  };
  add(event.app_user_id);
  add(event.original_app_user_id);
  for (const key of ["aliases", "transferred_from", "transferred_to"]) {
    const list = event[key];
    if (Array.isArray(list)) list.forEach(add);
  }
  return [...ids];
}

/// El plan efectivo según los entitlements vigentes a [nowMs].
export function planFrom(subscriber: Subscriber, nowMs: number): {
  tier: string;
  status: "active" | "expired";
  periodEnd: string | null;
  product: string | null;
} {
  const entitlements = subscriber.entitlements ?? {};
  const activeUntil = (e: Entitlement): number | null => {
    // Sin fecha de vencimiento = vitalicio / promocional sin fin: vigente.
    if (e.expires_date == null) return Number.POSITIVE_INFINITY;
    const ends = Math.max(
      Date.parse(e.expires_date),
      e.grace_period_expires_date ? Date.parse(e.grace_period_expires_date) : 0,
    );
    return ends > nowMs ? ends : null;
  };
  for (const tier of config.tiers) {
    const e = entitlements[tier];
    if (!e) continue;
    const until = activeUntil(e);
    if (until === null) continue;
    return {
      tier,
      status: "active",
      periodEnd: Number.isFinite(until) ? new Date(until).toISOString() : null,
      product: e.product_identifier ?? null,
    };
  }
  return { tier: "free", status: "expired", periodEnd: null, product: null };
}

async function fetchSubscriber(deps: Deps, userId: string): Promise<Subscriber | null> {
  const key = deps.env("REVENUECAT_SECRET_API_KEY");
  if (!key) return null;
  for (let attempt = 0; ; attempt++) {
    try {
      const response = await deps.fetch(
        `${config.apiBase}/subscribers/${encodeURIComponent(userId)}`,
        { headers: { Authorization: `Bearer ${key}`, Accept: "application/json" } },
      );
      if (response.ok) {
        const body = await response.json();
        return (body?.subscriber ?? {}) as Subscriber;
      }
      await response.body?.cancel();
      if (response.status < 500 && response.status !== 429) return null;
    } catch {
      // Red: se reintenta.
    }
    if (attempt >= config.retryDelaysMs.length) return null;
    await sleep(config.retryDelaysMs[attempt]);
  }
}

/// Formato de PaywallSource en la app. El atributo lo setea el cliente, así
/// que lo que no cumpla el formato no se guarda (podría ser cualquier texto).
const paywallSourceRe = /^[a-z][a-z0-9_]{2,59}$/;

const str = (v: unknown, max = 200): string | null =>
  typeof v === "string" && v.trim() !== "" ? v.trim().slice(0, max) : null;

/// Número finito que entra en numeric(precision, scale); si no, null (un valor
/// fuera de rango haría fallar el insert y RevenueCat reintentaría para siempre).
const num = (v: unknown, intDigits: number): number | null => {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
  return Number.isFinite(n) && Math.abs(n) < 10 ** intDigits ? n : null;
};

const msToIso = (v: unknown): string | null => {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
  if (!Number.isFinite(n)) return null;
  const d = new Date(n);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
};

/// Fila de subscription_events para [event] (función pura, sin base).
/// Solo campos conocidos: nunca el evento crudo ni otros subscriber_attributes.
export function eventRow(event: Record<string, unknown>): Record<string, unknown> {
  const appUserId = typeof event.app_user_id === "string" && uuidRe.test(event.app_user_id)
    ? event.app_user_id.toLowerCase()
    : null;
  const periodType = str(event.period_type, 40);
  const attrs = event.subscriber_attributes as Record<string, unknown> | undefined;
  const sourceAttr = attrs && typeof attrs === "object"
    ? (attrs.paywall_source as Record<string, unknown> | undefined)
    : undefined;
  const source = sourceAttr && typeof sourceAttr === "object" ? sourceAttr.value : undefined;
  return {
    event_id: str(event.id),
    user_id: appUserId ?? affectedUserIds(event)[0] ?? null,
    event_type: str(event.type, 60),
    product_id: str(event.product_id),
    new_product_id: str(event.new_product_id),
    store: str(event.store, 40),
    period_type: periodType,
    is_trial: periodType === "TRIAL",
    environment: str(event.environment, 40),
    price_usd: num(event.price, 8),
    price_local: num(event.price_in_purchased_currency, 10),
    currency: str(event.currency, 10),
    takehome_pct: num(event.takehome_percentage, 1),
    paywall_source: typeof source === "string" && paywallSourceRe.test(source) ? source : null,
    reason: str(event.cancel_reason, 60) ?? str(event.expiration_reason, 60),
    event_at: msToIso(event.event_timestamp_ms),
    purchased_at: msToIso(event.purchased_at_ms),
    expires_at: msToIso(event.expiration_at_ms),
  };
}

/// Guarda el evento; devuelve el mensaje de error o null. Un user_id que ya
/// no existe en auth.users (cuenta borrada) violaría la FK: se guarda igual,
/// sin usuario, para no perder el ingreso ni trabar los reintentos.
async function storeEvent(deps: Deps, row: Record<string, unknown>): Promise<string | null> {
  const insert = (r: Record<string, unknown>) =>
    deps.db.from("subscription_events").upsert(r, { onConflict: "event_id", ignoreDuplicates: true });
  try {
    let { error } = await insert(row);
    if (error?.code === "23503" && row.user_id != null) {
      ({ error } = await insert({ ...row, user_id: null }));
    }
    return error ? error.message : null;
  } catch (e) {
    return e instanceof Error ? e.message : String(e);
  }
}

async function log(
  deps: Deps,
  row: { user_id?: string; event_id?: string; event_type?: string; outcome: string; detail?: string },
) {
  const { error } = await deps.db.from("subscription_sync_log").insert(row);
  if (error) console.error("subscription_sync_log insert failed", error.message);
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");

  // Falla cerrado: sin secreto configurado, nadie puede cambiar planes.
  const secret = deps.env("REVENUECAT_WEBHOOK_SECRET");
  if (!secret) return typedError(500, "misconfigured", "Webhook secret not set");
  if (req.headers.get("authorization") !== `Bearer ${secret}`) {
    return typedError(401, "unauthorized", "Invalid webhook authorization");
  }

  let payload: { event?: Record<string, unknown> };
  try {
    payload = await req.json();
  } catch {
    return typedError(400, "invalid_json", "Body must be JSON");
  }
  const event = payload.event ?? {};
  const eventId = typeof event.id === "string" ? event.id : undefined;
  const eventType = typeof event.type === "string" ? event.type : undefined;

  // 1. Guardar el evento (también los TEST y los anónimos). Sin id o tipo no
  //    hay clave de idempotencia: se sigue como antes, sin fila.
  let storeError: string | null = null;
  if (eventId && eventType) {
    storeError = await storeEvent(deps, eventRow(event));
    if (storeError) {
      await log(deps, { event_id: eventId, event_type: eventType, outcome: "event_store_error", detail: storeError });
    }
  }
  const storeFailed = () => typedError(500, "event_store_error", "Could not store subscription event");

  // 2. Recalcular el plan, como siempre.
  const userIds = affectedUserIds(event);
  if (userIds.length === 0) {
    await log(deps, { event_id: eventId, event_type: eventType, outcome: "ignored", detail: "no app user id" });
    if (storeError) return storeFailed();
    return json(200, { ok: true, ignored: true });
  }

  const results: Record<string, string> = {};
  for (const userId of userIds) {
    const subscriber = await fetchSubscriber(deps, userId);
    if (!subscriber) {
      await log(deps, { user_id: userId, event_id: eventId, event_type: eventType, outcome: "revenuecat_unavailable" });
      // Estado anterior intacto; RevenueCat reintenta ante un no-2xx.
      return typedError(503, "revenuecat_unavailable", "Could not read subscriber");
    }
    const plan = planFrom(subscriber, deps.now());
    const { error } = await deps.db.rpc("upsert_subscription_from_provider", {
      p_user_id: userId,
      p_tier: plan.tier,
      p_provider: "revenuecat",
      p_external_subscription_id: plan.product,
      p_status: plan.status,
      p_current_period_end: plan.periodEnd,
    });
    if (error) {
      await log(deps, { user_id: userId, event_id: eventId, event_type: eventType, outcome: "db_error", detail: error.message });
      return typedError(500, "db_error", error.message);
    }
    results[userId] = plan.tier;
    await log(deps, { user_id: userId, event_id: eventId, event_type: eventType, outcome: `synced:${plan.tier}` });
  }
  // 3. El plan quedó bien pero el evento no: 500 para que RevenueCat reintente
  //    (las dos operaciones son idempotentes).
  if (storeError) return storeFailed();
  return json(200, { ok: true, tiers: results });
}

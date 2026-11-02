// Webhook de RevenueCat: plan por usuario (user_subscriptions) y registro de
// cada evento en subscription_events.
//
// Los tests "[sin base]" corren sin stack (eventRow puro y una base falsa):
//   deno test --allow-net --allow-env --allow-read --filter "[sin base]" tests/revenuecat_webhook_test.ts
// El resto necesita `supabase start` y las variables de `supabase status -o env`.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { eventRow, handle } from "../revenuecat-webhook/handler.ts";
import { createUser, db, deps, fakeFetch } from "./helpers.ts";

const SECRET = "whsec-test";
const env = { REVENUECAT_WEBHOOK_SECRET: SECRET, REVENUECAT_SECRET_API_KEY: "sk_rc_test" };
const day = 24 * 60 * 60 * 1000;
const iso = (ms: number) => new Date(ms).toISOString();

type Ent = { expires_date: string | null; product_identifier?: string };

/// RevenueCat falso: devuelve el estado que el test fue armando.
function revenueCat(state: { entitlements: Record<string, Ent> } | "down") {
  return fakeFetch(() =>
    state === "down"
      ? new Response("oops", { status: 503 })
      : Response.json({ subscriber: { entitlements: state.entitlements } })
  );
}

function event(userId: string, type: string, extra: Record<string, unknown> = {}): Request {
  return new Request("http://local/revenuecat-webhook", {
    method: "POST",
    headers: { Authorization: `Bearer ${SECRET}`, "Content-Type": "application/json" },
    body: JSON.stringify({ event: { id: crypto.randomUUID(), type, app_user_id: userId, ...extra } }),
  });
}

async function tierOf(userId: string) {
  const { data } = await db.from("user_subscriptions").select("tier, status").eq("user_id", userId).single();
  return data as { tier: string; status: string };
}

Deno.test("sin secreto configurado o con header incorrecto: no toca nada", async () => {
  const user = await createUser("free");
  const rc = revenueCat({ entitlements: { gold: { expires_date: null } } });
  const noSecret = await handle(event(user.id, "INITIAL_PURCHASE"), deps(rc.fetch, {}));
  assertEquals(noSecret.status, 500);
  const bad = new Request("http://local/x", { method: "POST", headers: { Authorization: "Bearer nope" }, body: "{}" });
  assertEquals((await handle(bad, deps(rc.fetch, env))).status, 401);
  assertEquals((await tierOf(user.id)).tier, "free");
  assertEquals(rc.calls.length, 0);
});

Deno.test("compra Premium → promo Gold → vence la promo: queda Premium (antes caía a Free)", async () => {
  const user = await createUser("free");
  const now = Date.now();
  const premium = { expires_date: iso(now + 20 * day), product_identifier: "portfolio_premium_monthly" };
  let state = { entitlements: { premium } as Record<string, Ent> };
  const d = () => deps(revenueCat(state).fetch, env, () => now);

  await handle(event(user.id, "INITIAL_PURCHASE"), d());
  assertEquals((await tierOf(user.id)).tier, "premium");

  state = { entitlements: { premium, gold: { expires_date: iso(now + 7 * day), product_identifier: "rc_promo_gold_weekly" } } };
  await handle(event(user.id, "NON_RENEWING_PURCHASE"), d());
  assertEquals((await tierOf(user.id)).tier, "gold");

  state = { entitlements: { premium, gold: { expires_date: iso(now - day) } } };
  await handle(event(user.id, "EXPIRATION", { product_id: "rc_promo_gold_weekly" }), d());
  assertEquals(await tierOf(user.id), { tier: "premium", status: "active" });
});

Deno.test("Gold mensual → anual: sigue en Gold", async () => {
  const user = await createUser("gold");
  const now = Date.now();
  const rc = revenueCat({ entitlements: { gold: { expires_date: iso(now + 365 * day), product_identifier: "portfolio_gold_annual" } } });
  await handle(event(user.id, "PRODUCT_CHANGE", { product_id: "portfolio_gold_monthly" }), deps(rc.fetch, env, () => now));
  assertEquals((await tierOf(user.id)).tier, "gold");
});

Deno.test("cancelación con período vigente: mantiene el plan hasta que vence (antes quedaba 'canceled' = Free)", async () => {
  const user = await createUser("gold");
  const now = Date.now();
  const rc = revenueCat({ entitlements: { gold: { expires_date: iso(now + 10 * day) } } });
  await handle(event(user.id, "CANCELLATION"), deps(rc.fetch, env, () => now));
  assertEquals(await tierOf(user.id), { tier: "gold", status: "active" });
});

Deno.test("eventos duplicados y desordenados: manda el estado actual de RevenueCat", async () => {
  const user = await createUser("free");
  const now = Date.now();
  const rc = revenueCat({ entitlements: { gold: { expires_date: iso(now + 30 * day) } } });
  const d = deps(rc.fetch, env, () => now);
  // Llega primero un EXPIRATION viejo, después el RENEWAL, y el RENEWAL repetido.
  await handle(event(user.id, "EXPIRATION"), d);
  await handle(event(user.id, "RENEWAL"), d);
  await handle(event(user.id, "RENEWAL"), d);
  assertEquals((await tierOf(user.id)).tier, "gold");
});

Deno.test("RevenueCat caído: no baja de plan, responde 503 (para que reintente) y lo registra", async () => {
  const user = await createUser("gold");
  const r = await handle(event(user.id, "EXPIRATION"), deps(revenueCat("down").fetch, env));
  assertEquals(r.status, 503);
  assertEquals((await tierOf(user.id)).tier, "gold");
  const { data } = await db.from("subscription_sync_log").select("outcome").eq("user_id", user.id);
  assertEquals(data?.some((row) => row.outcome === "revenuecat_unavailable"), true);
});

Deno.test("ids anónimos de RevenueCat se ignoran sin error", async () => {
  const rc = revenueCat({ entitlements: {} });
  const r = await handle(event("$RCAnonymousID:abc", "INITIAL_PURCHASE"), deps(rc.fetch, env));
  assertEquals(r.status, 200);
  assertEquals(rc.calls.length, 0);
});

// ---------------------------------------------------------------------------
// subscription_events
// ---------------------------------------------------------------------------

const purchasedMs = 1762100000000;

/// Evento completo de §3.9 de la spec, para [userId].
function fullEvent(userId: string, extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: crypto.randomUUID(),
    type: "INITIAL_PURCHASE",
    app_user_id: userId,
    original_app_user_id: userId,
    aliases: [userId],
    product_id: "portfolio_premium_annual",
    new_product_id: null,
    store: "APP_STORE",
    period_type: "NORMAL",
    environment: "PRODUCTION",
    price: 99.99,
    price_in_purchased_currency: 89.5,
    currency: "EUR",
    takehome_percentage: 0.85,
    subscriber_attributes: {
      paywall_source: { value: "add_position_limit", updated_at_ms: purchasedMs },
      $email: { value: "persona@ejemplo.com", updated_at_ms: purchasedMs },
    },
    cancel_reason: null,
    expiration_reason: null,
    event_timestamp_ms: purchasedMs,
    purchased_at_ms: purchasedMs,
    expiration_at_ms: purchasedMs + 365 * day,
    ...extra,
  };
}

function post(event: Record<string, unknown>): Request {
  return new Request("http://local/revenuecat-webhook", {
    method: "POST",
    headers: { Authorization: `Bearer ${SECRET}`, "Content-Type": "application/json" },
    body: JSON.stringify({ event }),
  });
}

type Call = { table?: string; op: string; row?: Record<string, unknown>; options?: unknown };

/// Base falsa mínima: guarda cada operación. [storeError] hace fallar el
/// upsert de subscription_events.
function fakeDb(storeError: { message: string; code?: string }[] = []) {
  const calls: Call[] = [];
  const client = {
    from: (table: string) => ({
      insert: (row: Record<string, unknown>) => {
        calls.push({ table, op: "insert", row });
        return Promise.resolve({ error: null });
      },
      upsert: (row: Record<string, unknown>, options: unknown) => {
        calls.push({ table, op: "upsert", row, options });
        return Promise.resolve({ error: storeError.shift() ?? null });
      },
    }),
    rpc: (fn: string, args: Record<string, unknown>) => {
      calls.push({ op: `rpc:${fn}`, row: args });
      return Promise.resolve({ error: null });
    },
  };
  return { db: client as unknown as SupabaseClient, calls };
}

function fakeDeps(fake: ReturnType<typeof fakeDb>, fetchImpl: typeof fetch) {
  return {
    db: fake.db,
    authenticate: () => Promise.resolve(null),
    fetch: fetchImpl,
    env: (name: string) => (env as Record<string, string>)[name],
    now: () => purchasedMs,
    background: () => {},
  };
}

const goldForever = () => revenueCat({ entitlements: { gold: { expires_date: null } } });

Deno.test("[sin base] eventRow: mapea los campos de la spec y nada más", () => {
  const userId = crypto.randomUUID();
  const row = eventRow(fullEvent(userId.toUpperCase()));
  assertEquals(row, {
    event_id: row.event_id,
    user_id: userId,
    event_type: "INITIAL_PURCHASE",
    product_id: "portfolio_premium_annual",
    new_product_id: null,
    store: "APP_STORE",
    period_type: "NORMAL",
    is_trial: false,
    environment: "PRODUCTION",
    price_usd: 99.99,
    price_local: 89.5,
    currency: "EUR",
    takehome_pct: 0.85,
    paywall_source: "add_position_limit",
    reason: null,
    event_at: new Date(purchasedMs).toISOString(),
    purchased_at: new Date(purchasedMs).toISOString(),
    expires_at: new Date(purchasedMs + 365 * day).toISOString(),
  });
  // Nunca otros atributos (pueden traer datos personales).
  assert(!JSON.stringify(row).includes("persona@ejemplo.com"));
});

Deno.test("[sin base] eventRow: trial, motivo, anónimo, alias y valores raros", () => {
  const userId = crypto.randomUUID();
  assertEquals(eventRow(fullEvent(userId, { period_type: "TRIAL" })).is_trial, true);
  assertEquals(eventRow(fullEvent(userId, { cancel_reason: "UNSUBSCRIBE" })).reason, "UNSUBSCRIBE");
  assertEquals(eventRow(fullEvent(userId, { expiration_reason: "BILLING_ERROR" })).reason, "BILLING_ERROR");

  // Anónimo de RevenueCat: sin usuario.
  const anon = eventRow({ id: "e1", type: "TEST", app_user_id: "$RCAnonymousID:abc" });
  assertEquals(anon.user_id, null);
  assertEquals(anon.is_trial, false);
  assertEquals(anon.price_usd, null);
  assertEquals(anon.event_at, null);

  // app_user_id anónimo pero con alias de la app: el primero de affectedUserIds.
  const aliased = eventRow({ id: "e2", type: "RENEWAL", app_user_id: "$RCAnonymousID:x", aliases: [userId] });
  assertEquals(aliased.user_id, userId);

  // paywall_source lo setea el cliente: si no cumple el formato, no se guarda.
  const bad = eventRow(fullEvent(userId, {
    subscriber_attributes: { paywall_source: { value: "Hola <script>" } },
  }));
  assertEquals(bad.paywall_source, null);
  assertEquals(eventRow(fullEvent(userId, { subscriber_attributes: null })).paywall_source, null);

  // Números fuera de rango o no numéricos → null (no rompen el insert).
  const weird = eventRow(fullEvent(userId, { price: 1e12, price_in_purchased_currency: "abc", takehome_percentage: "0.7" }));
  assertEquals([weird.price_usd, weird.price_local, weird.takehome_pct], [null, null, 0.7]);
  // Reembolso: precio negativo.
  assertEquals(eventRow(fullEvent(userId, { type: "CANCELLATION", price: -99.99 })).price_usd, -99.99);
});

Deno.test("[sin base] guarda el evento antes de recalcular, idempotente por event_id", async () => {
  const fake = fakeDb();
  const userId = crypto.randomUUID();
  const r = await handle(post(fullEvent(userId)), fakeDeps(fake, goldForever().fetch));
  assertEquals(r.status, 200);
  assertEquals(fake.calls[0].table, "subscription_events");
  assertEquals(fake.calls[0].op, "upsert");
  assertEquals(fake.calls[0].options, { onConflict: "event_id", ignoreDuplicates: true });
  assertEquals(fake.calls[0].row?.user_id, userId);
  assertEquals(fake.calls[1].op, "rpc:upsert_subscription_from_provider");
});

Deno.test("[sin base] si guardar falla: recalcula el plan, registra event_store_error y responde 500", async () => {
  const fake = fakeDb([{ message: "relation does not exist", code: "42P01" }]);
  const userId = crypto.randomUUID();
  const r = await handle(post(fullEvent(userId)), fakeDeps(fake, goldForever().fetch));
  assertEquals(r.status, 500);
  assertEquals((await r.json()).error.type, "event_store_error");
  assert(fake.calls.some((c) => c.op === "rpc:upsert_subscription_from_provider" && c.row?.p_tier === "gold"));
  const outcomes = fake.calls.filter((c) => c.table === "subscription_sync_log").map((c) => c.row?.outcome);
  assert(outcomes.includes("event_store_error"));
  assert(outcomes.includes("synced:gold"));
});

Deno.test("[sin base] si guardar falla en un evento anónimo: 500 (antes 200 ignored)", async () => {
  const fake = fakeDb([{ message: "boom" }]);
  const r = await handle(post({ id: "e-anon", type: "TEST", app_user_id: "$RCAnonymousID:abc" }), fakeDeps(fake, goldForever().fetch));
  assertEquals(r.status, 500);
});

Deno.test("[sin base] usuario borrado (FK): se guarda sin usuario", async () => {
  const fake = fakeDb([{ message: "violates foreign key constraint", code: "23503" }]);
  const userId = crypto.randomUUID();
  const r = await handle(post(fullEvent(userId)), fakeDeps(fake, goldForever().fetch));
  assertEquals(r.status, 200);
  const upserts = fake.calls.filter((c) => c.op === "upsert");
  assertEquals(upserts.map((c) => c.row?.user_id), [userId, null]);
});

Deno.test("[sin base] evento sin id o sin type: no guarda fila y sigue como antes", async () => {
  const fake = fakeDb();
  const userId = crypto.randomUUID();
  const r = await handle(post({ type: "RENEWAL", app_user_id: userId }), fakeDeps(fake, goldForever().fetch));
  assertEquals(r.status, 200);
  assertEquals(fake.calls.filter((c) => c.table === "subscription_events").length, 0);
});

async function eventRows(eventId: string) {
  const { data, error } = await db.from("subscription_events").select("*").eq("event_id", eventId);
  if (error) throw error;
  return data as Record<string, unknown>[];
}

Deno.test("INITIAL_PURCHASE completo: deja la fila con todos los campos", async () => {
  const user = await createUser("free");
  const ev = fullEvent(user.id);
  const r = await handle(post(ev), deps(goldForever().fetch, env));
  assertEquals(r.status, 200);
  const [row] = await eventRows(ev.id as string);
  assertEquals(row.user_id, user.id);
  assertEquals(Number(row.price_usd), 99.99);
  assertEquals(Number(row.price_local), 89.5);
  assertEquals(Number(row.takehome_pct), 0.85);
  assertEquals(
    [row.currency, row.store, row.period_type, row.environment, row.is_sandbox, row.is_trial],
    ["EUR", "APP_STORE", "NORMAL", "PRODUCTION", false, false],
  );
  assertEquals([row.product_id, row.paywall_source], ["portfolio_premium_annual", "add_position_limit"]);
  assertEquals(Date.parse(row.event_at as string), purchasedMs);
  assertEquals(Date.parse(row.expires_at as string), purchasedMs + 365 * day);
});

Deno.test("TRIAL y SANDBOX: is_trial e is_sandbox en true", async () => {
  const user = await createUser("free");
  const ev = fullEvent(user.id, { period_type: "TRIAL", environment: "SANDBOX" });
  await handle(post(ev), deps(goldForever().fetch, env));
  const [row] = await eventRows(ev.id as string);
  assertEquals([row.is_trial, row.is_sandbox], [true, true]);
});

Deno.test("mismo event.id dos veces: una sola fila y el plan igual", async () => {
  const user = await createUser("free");
  const ev = fullEvent(user.id);
  const d = deps(goldForever().fetch, env);
  assertEquals((await handle(post(ev), d)).status, 200);
  assertEquals((await handle(post(ev), d)).status, 200);
  assertEquals((await eventRows(ev.id as string)).length, 1);
  assertEquals(await tierOf(user.id), { tier: "gold", status: "active" });
});

Deno.test("anónimo de RevenueCat: fila con user_id null y respuesta ignored", async () => {
  const rc = goldForever();
  const ev = { id: crypto.randomUUID(), type: "INITIAL_PURCHASE", app_user_id: "$RCAnonymousID:abc", environment: "SANDBOX" };
  const r = await handle(post(ev), deps(rc.fetch, env));
  assertEquals(await r.json(), { ok: true, ignored: true });
  assertEquals(rc.calls.length, 0);
  const [row] = await eventRows(ev.id);
  assertEquals(row.user_id, null);
});

/// La base real, salvo subscription_events, que siempre falla.
function dbWithBrokenEvents(): SupabaseClient {
  return new Proxy(db, {
    get(target, prop) {
      if (prop === "from") {
        return (table: string) =>
          table === "subscription_events"
            ? target.from("subscription_events_renombrada")
            : target.from(table);
      }
      const value = Reflect.get(target, prop, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

Deno.test("si el insert falla: el plan se recalcula, queda event_store_error y responde 500", async () => {
  const user = await createUser("free");
  const ev = fullEvent(user.id);
  const r = await handle(post(ev), { ...deps(goldForever().fetch, env), db: dbWithBrokenEvents() });
  assertEquals(r.status, 500);
  assertEquals((await r.json()).error.type, "event_store_error");
  assertEquals((await tierOf(user.id)).tier, "gold");
  const { data } = await db.from("subscription_sync_log").select("outcome").eq("event_id", ev.id as string);
  assertEquals(data?.some((row) => row.outcome === "event_store_error"), true);
  assertEquals((await eventRows(ev.id as string)).length, 0);
});

Deno.test("con JWT de authenticated: subscription_events no se lee ni se escribe", async () => {
  const user = await createUser("free");
  const url = Deno.env.get("API_URL") ?? Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
  const anonKey = Deno.env.get("ANON_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const asUser = createClient(url, anonKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${user.jwt}` } },
  });
  const read = await asUser.from("subscription_events").select("id").limit(1);
  assertEquals(read.error?.code, "42501");
  const write = await asUser.from("subscription_events").insert({ event_id: crypto.randomUUID(), event_type: "TEST" });
  assertEquals(write.error?.code, "42501");
  const funnel = await asUser.from("product_funnel").select("user_id").limit(1);
  assertEquals(funnel.error?.code, "42501");
});

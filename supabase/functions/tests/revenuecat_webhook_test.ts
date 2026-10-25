import { assertEquals } from "jsr:@std/assert@1";
import { handle } from "../revenuecat-webhook/handler.ts";
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

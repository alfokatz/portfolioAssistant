// Tests del handler de la landing. La lógica de datos (RLS, checks de la
// tabla, `landing_stats` y `landing_sources`) se prueba contra Postgres en
// supabase/tests/landing_db_test.sql; acá va lo del handler (validación,
// rate limit, proxy) con una base falsa, así corre sin `supabase start`.

import { assert, assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { Deps } from "../_shared/common.ts";
import { handle, ipHash } from "../landing/handler.ts";

type Call = { kind: "rpc" | "insert"; name: string; args: Record<string, unknown> };

function fakeDb(opts: { rateOk?: boolean } = {}) {
  const calls: Call[] = [];
  const db = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ kind: "rpc", name, args });
      if (name === "landing_rate_hit") return Promise.resolve({ data: opts.rateOk ?? true, error: null });
      return Promise.resolve({ data: null, error: { message: "unknown rpc" } });
    },
    from: (name: string) => ({
      insert: (args: Record<string, unknown>) => {
        calls.push({ kind: "insert", name, args });
        return Promise.resolve({ error: null });
      },
    }),
  };
  return { db: db as unknown as SupabaseClient, calls };
}

function deps(db: SupabaseClient, env: Record<string, string> = {}): Deps {
  return {
    db,
    authenticate: () => Promise.resolve(null),
    fetch: () => Promise.reject(new Error("no network")),
    env: (k) => env[k],
    now: () => Date.parse("2026-10-13T12:00:00Z"),
    background: () => {},
  };
}

const env = { LANDING_PROXY_SECRET: "s3cret", LANDING_IP_SALT: "salt" };

function req(route: string, body: unknown, headers: Record<string, string> = {}): Request {
  return new Request(`http://local/functions/v1/landing/${route}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const proxied = {
  "x-landing-proxy-secret": "s3cret",
  "x-landing-ip": "203.0.113.7",
  "x-landing-country": "ar",
};

const anonId = "6f1c2a4e-1111-2222-3333-444455556666";

Deno.test("store_click válido → inserta tienda, país del proxy y UTM, sin IP", async () => {
  const f = fakeDb();
  const r = await handle(
    req("event", {
      anon_id: anonId,
      event: "store_click",
      store: "ios",
      variant: "b",
      path: "/",
      utm: { utm_source: "tiktok", utm_campaign: "x".repeat(300), other: "no" },
    }, proxied),
    deps(f.db, env),
  );
  assertEquals(r.status, 204);

  const rate = f.calls.find((c) => c.name === "landing_rate_hit")!;
  assertEquals(rate.args.p_bucket, "event");
  assert(!JSON.stringify(f.calls).includes("203.0.113.7"), "la IP no puede viajar en claro");

  const insert = f.calls.find((c) => c.kind === "insert")!;
  assertEquals(insert.name, "landing_events");
  assertEquals(insert.args.store, "ios");
  assertEquals(insert.args.country, "AR");
  assertEquals(insert.args.variant, "b");
  assertEquals(insert.args.utm_source, "tiktok");
  assertEquals((insert.args.utm_campaign as string).length, 100);
  assertEquals("other" in insert.args, false);
});

Deno.test("store_click sin tienda válida → 400 sin tocar la base", async () => {
  for (const store of [undefined, "windows", 1]) {
    const f = fakeDb();
    const r = await handle(req("event", { anon_id: anonId, event: "store_click", store }, proxied), deps(f.db, env));
    assertEquals(r.status, 400, String(store));
    assertEquals((await r.json()).error.type, "invalid_store");
    assertEquals(f.calls.length, 0);
  }
});

Deno.test("plan_click → inserta el plan y store null", async () => {
  const f = fakeDb();
  const r = await handle(
    req("event", {
      anon_id: anonId,
      event: "plan_click",
      plan: "premium",
      store: "ios",
      variant: "a",
      path: "/precios",
      utm: { utm_source: "meta" },
    }, proxied),
    deps(f.db, env),
  );
  assertEquals(r.status, 204);
  assertEquals(f.calls.find((c) => c.kind === "insert")!.args, {
    anon_id: anonId,
    variant: "a",
    event: "plan_click",
    plan: "premium",
    store: null,
    country: "AR",
    path: "/precios",
    utm_source: "meta",
  });
});

Deno.test("eventos de la lista de espera ya no se aceptan", async () => {
  for (const event of ["signup", "founder_signup", "form_view", "founder_modal_open", "nada"]) {
    const f = fakeDb();
    const r = await handle(req("event", { anon_id: anonId, event }, proxied), deps(f.db, env));
    assertEquals(r.status, 400, event);
    assertEquals(f.calls.length, 0);
  }
});

Deno.test("anon_id inválido → 400", async () => {
  const f = fakeDb();
  const r = await handle(req("event", { anon_id: "x", event: "page_view" }, proxied), deps(f.db, env));
  assertEquals(r.status, 400);
  assertEquals(f.calls.length, 0);
});

Deno.test("rate limit → 429 sin registrar", async () => {
  const f = fakeDb({ rateOk: false });
  const r = await handle(req("event", { anon_id: anonId, event: "page_view" }, proxied), deps(f.db, env));
  assertEquals(r.status, 429);
  assertEquals(f.calls.some((c) => c.kind === "insert"), false);
});

Deno.test("sin el secreto del proxy no se confía en el país ni en la IP del header", async () => {
  const f = fakeDb();
  await handle(
    req("event", { anon_id: anonId, event: "page_view" }, {
      ...proxied,
      "x-landing-proxy-secret": "otro",
      "x-forwarded-for": "198.51.100.1",
    }),
    deps(f.db, env),
  );
  assertEquals(f.calls.find((c) => c.kind === "insert")!.args.country, null);
  const hash = f.calls.find((c) => c.name === "landing_rate_hit")!.args.p_key_hash;
  assertEquals(hash, await ipHash("198.51.100.1", deps(f.db, env)));
});

Deno.test("/signup → 410 (la lista de espera cerró) sin tocar la base", async () => {
  const f = fakeDb();
  const r = await handle(req("signup", { email: "a@b.co", consent: true, variant: "a" }, proxied), deps(f.db, env));
  assertEquals(r.status, 410);
  assertEquals((await r.json()).error.type, "waitlist_closed");
  assertEquals(f.calls.length, 0);
});

Deno.test("ruta desconocida, método y body", async () => {
  const f = fakeDb();
  assertEquals((await handle(req("otra", {}, proxied), deps(f.db, env))).status, 404);
  assertEquals((await handle(new Request("http://local/landing/event"), deps(f.db, env))).status, 405);
  const bad = new Request("http://local/landing/event", { method: "POST", body: "[1]" });
  assertEquals((await handle(bad, deps(f.db, env))).status, 400);
});

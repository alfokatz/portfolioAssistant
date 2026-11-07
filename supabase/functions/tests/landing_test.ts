// Tests del handler de la landing. La lógica de datos (alta idempotente,
// puesto, referidos, eventos del servidor, RLS y `landing_stats`) se prueba
// contra Postgres en supabase/tests/landing_db_test.sql; acá va lo del
// handler (validación, honeypot, rate limit, proxy) con una base falsa, así
// corre sin `supabase start`.

import { assert, assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { Deps } from "../_shared/common.ts";
import { handle, ipHash, isEmail } from "../landing/handler.ts";

type Call = { kind: "rpc" | "insert"; name: string; args: Record<string, unknown> };

function fakeDb(opts: { rateOk?: boolean } = {}) {
  const calls: Call[] = [];
  const db = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ kind: "rpc", name, args });
      if (name === "landing_rate_hit") return Promise.resolve({ data: opts.rateOk ?? true, error: null });
      if (name === "landing_signup") {
        return Promise.resolve({ data: { position: 42, ref_code: "ABC234", created: true }, error: null });
      }
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

const validSignup = {
  email: "Ana@Example.com",
  consent: true,
  variant: "b",
  website: "",
  utm: { utm_source: "tiktok", utm_campaign: "x".repeat(300), other: "no" },
  referred_by: "abc234",
  anon_id: "6f1c2a4e-1111-2222-3333-444455556666",
  path: "/",
};

Deno.test("signup válido → llama landing_signup con país del proxy y devuelve puesto y código", async () => {
  const f = fakeDb();
  const r = await handle(req("signup", validSignup, proxied), deps(f.db, env));
  assertEquals(r.status, 200);
  assertEquals(await r.json(), { position: 42, ref_code: "ABC234" });

  const rate = f.calls.find((c) => c.name === "landing_rate_hit")!;
  assertEquals(rate.args.p_bucket, "signup");
  assert(!JSON.stringify(rate.args).includes("203.0.113.7"), "la IP no puede viajar en claro");

  const call = f.calls.find((c) => c.name === "landing_signup")!;
  assertEquals(call.args.p_variant, "b");
  assertEquals(call.args.p_country, "AR");
  assertEquals(call.args.p_referred_by, "ABC234");
  assertEquals(call.args.p_intended_plan, null);
  const utm = call.args.p_utm as Record<string, string>;
  assertEquals(utm.utm_source, "tiktok");
  assertEquals(utm.utm_campaign.length, 100);
  assertEquals("other" in utm, false);
});

Deno.test("signup con plan del modal fundador → pasa intended_plan", async () => {
  const f = fakeDb();
  const r = await handle(req("signup", { ...validSignup, intended_plan: "gold" }, proxied), deps(f.db, env));
  assertEquals(r.status, 200);
  assertEquals(f.calls.find((c) => c.name === "landing_signup")!.args.p_intended_plan, "gold");
});

Deno.test("honeypot con algo → 200 sin tocar la base", async () => {
  const f = fakeDb();
  const r = await handle(req("signup", { ...validSignup, website: "http://spam" }, proxied), deps(f.db, env));
  assertEquals(r.status, 200);
  assertEquals(await r.json(), { position: null, ref_code: null });
  assertEquals(f.calls.length, 0);
});

Deno.test("validación: email, consentimiento, variante y plan", async () => {
  const cases: [Record<string, unknown>, string][] = [
    [{ email: "no-es-email" }, "invalid_email"],
    [{ consent: false }, "consent_required"],
    [{ variant: "d" }, "invalid_variant"],
    [{ intended_plan: "platinum" }, "invalid_plan"],
  ];
  for (const [patch, type] of cases) {
    const f = fakeDb();
    const r = await handle(req("signup", { ...validSignup, ...patch }, proxied), deps(f.db, env));
    assertEquals(r.status, 400, type);
    assertEquals((await r.json()).error.type, type);
    assertEquals(f.calls.length, 0);
  }
});

Deno.test("rate limit → 429 sin registrar", async () => {
  const f = fakeDb({ rateOk: false });
  const r = await handle(req("signup", validSignup, proxied), deps(f.db, env));
  assertEquals(r.status, 429);
  assertEquals(f.calls.some((c) => c.name === "landing_signup"), false);
});

Deno.test("sin el secreto del proxy no se confía en el país ni en la IP del header", async () => {
  const f = fakeDb();
  await handle(
    req("signup", validSignup, { ...proxied, "x-landing-proxy-secret": "otro", "x-forwarded-for": "198.51.100.1" }),
    deps(f.db, env),
  );
  assertEquals(f.calls.find((c) => c.name === "landing_signup")!.args.p_country, null);
  const hash = f.calls.find((c) => c.name === "landing_rate_hit")!.args.p_key_hash;
  assertEquals(hash, await ipHash("198.51.100.1", deps(f.db, env)));
});

Deno.test("event válido → inserta sin IP y responde 204", async () => {
  const f = fakeDb();
  const r = await handle(
    req("event", {
      anon_id: validSignup.anon_id,
      event: "plan_click",
      plan: "premium",
      variant: "a",
      path: "/precios",
      utm: { utm_source: "meta" },
    }, proxied),
    deps(f.db, env),
  );
  assertEquals(r.status, 204);
  const insert = f.calls.find((c) => c.kind === "insert")!;
  assertEquals(insert.name, "landing_events");
  assertEquals(insert.args, {
    anon_id: validSignup.anon_id,
    variant: "a",
    event: "plan_click",
    plan: "premium",
    path: "/precios",
    utm_source: "meta",
  });
});

Deno.test("event: el cliente no puede mandar signup ni founder_signup", async () => {
  for (const event of ["signup", "founder_signup", "nada"]) {
    const f = fakeDb();
    const r = await handle(req("event", { anon_id: validSignup.anon_id, event }, proxied), deps(f.db, env));
    assertEquals(r.status, 400, event);
    assertEquals(f.calls.length, 0);
  }
});

Deno.test("ruta desconocida, método y body", async () => {
  const f = fakeDb();
  assertEquals((await handle(req("otra", {}, proxied), deps(f.db, env))).status, 404);
  assertEquals((await handle(new Request("http://local/landing/signup"), deps(f.db, env))).status, 405);
  const bad = new Request("http://local/landing/signup", { method: "POST", body: "[1]" });
  assertEquals((await handle(bad, deps(f.db, env))).status, 400);
});

Deno.test("isEmail", () => {
  assert(isEmail("a@b.co"));
  assert(isEmail("  ana.perez+porty@gmail.com "));
  assert(!isEmail("a@b"));
  assert(!isEmail("a b@c.com"));
  assert(!isEmail(`${"a".repeat(250)}@b.com`));
});

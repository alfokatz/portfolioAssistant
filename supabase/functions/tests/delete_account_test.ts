// Edge function delete-account: orden de pasos, errores con nothingDeleted,
// idempotencia y borrado real.
//
// Los tests "[sin base]" usan una base falsa y corren sin stack:
//   deno test --allow-net --allow-env --allow-read --filter "[sin base]" tests/delete_account_test.ts
// El resto necesita `supabase start` y las variables de `supabase status -o env`
// (borran usuarios reales del stack local con auth.admin.deleteUser).
import { assert, assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { handle } from "../delete-account/handler.ts";
import { resetEtoroCaches } from "../etoro-sync/etoro.ts";
import { createUser, db, deps, fakeFetch } from "./helpers.ts";

const env = {
  REVENUECAT_SECRET_API_KEY: "sk_rc_test",
  SNAPTRADE_CLIENT_ID: "st-client",
  SNAPTRADE_CONSUMER_KEY: "st-key",
  ETORO_CLIENT_ID: "et-client",
  ETORO_CLIENT_SECRET: "et-secret",
};

type Upstream = { snaptrade?: number; revenuecat?: number | number[]; etoro?: number };

/// Proveedores falsos: status por proveedor (RevenueCat acepta una secuencia
/// para probar reintentos). El discovery de eToro responde 404 (usa el fallback).
function upstreams(status: Upstream = {}) {
  const rc = Array.isArray(status.revenuecat) ? [...status.revenuecat] : null;
  return fakeFetch((url) => {
    if (url.includes("snaptrade.com")) return new Response("{}", { status: status.snaptrade ?? 200 });
    if (url.includes("revenuecat.com")) {
      const s = rc ? (rc.length > 1 ? rc.shift()! : rc[0]) : (status.revenuecat as number | undefined) ?? 200;
      return new Response("{}", { status: s });
    }
    if (url.includes("openid-configuration")) return new Response("no", { status: 404 });
    if (url.includes("etoro.com")) return new Response("", { status: status.etoro ?? 200 });
    return new Response("unexpected", { status: 599 });
  });
}

/// Hosts llamados, sin el discovery de eToro (se pide en cada revoke si falla).
const hosts = (calls: { url: string }[]) =>
  calls.filter((c) => !c.url.includes("openid-configuration"))
    .map((c) => new URL(c.url).hostname + (c.url.includes("revoke") ? "/revoke" : ""));

function request(body: unknown = { confirm: true }, jwt: string | null = "jwt", method = "POST"): Request {
  return new Request("http://local/delete-account", {
    method,
    headers: { ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}), "Content-Type": "application/json" },
    ...(method === "POST" ? { body: typeof body === "string" ? body : JSON.stringify(body) } : {}),
  });
}

// ---------------------------------------------------------------------------
// Base falsa
// ---------------------------------------------------------------------------

type DbError = { message: string; code?: string; status?: number };

type FakeOpts = {
  snaptrade?: string | null;
  etoro?: string | null;
  rate?: boolean;
  rpcErrors?: Record<string, DbError>;
  deleteUserError?: DbError | null;
};

function fakeDb(opts: FakeOpts = {}) {
  const ops: string[] = [];
  const client = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      ops.push(`rpc:${fn}`);
      const error = opts.rpcErrors?.[fn] ?? null;
      if (error) return Promise.resolve({ data: null, error });
      if (fn === "rate_limit_hit") {
        assertEquals(args.p_bucket, "delete_account");
        return Promise.resolve({ data: opts.rate ?? true, error: null });
      }
      if (fn === "snaptrade_secret_read") return Promise.resolve({ data: opts.snaptrade ?? null, error: null });
      if (fn === "etoro_tokens_read") return Promise.resolve({ data: opts.etoro ?? null, error: null });
      if (fn.endsWith("_disconnect")) {
        assertEquals(args.p_keep_as_manual, true);
        return Promise.resolve({ data: { open: 0 }, error: null });
      }
      return Promise.resolve({ data: null, error: { message: `unexpected rpc ${fn}` } });
    },
    auth: {
      admin: {
        deleteUser: (_id: string) => {
          ops.push("auth:deleteUser");
          return Promise.resolve({ data: null, error: opts.deleteUserError ?? null });
        },
      },
    },
  };
  return { db: client as unknown as SupabaseClient, ops };
}

const UID = "11111111-2222-4333-8444-555555555555";

function fakeDeps(fake: ReturnType<typeof fakeDb>, fetchImpl: typeof fetch, e: Record<string, string> = env) {
  return {
    db: fake.db,
    authenticate: (jwt: string) => Promise.resolve(jwt === "jwt" ? UID : null),
    fetch: fetchImpl,
    env: (name: string) => e[name],
    now: () => Date.now(),
    background: () => {},
  };
}

const snapSecret = JSON.stringify({ user_id: "st-user", user_secret: "st-secret" });
const etoroTokens = JSON.stringify({ accessToken: "et-access", refreshToken: "et-refresh", expiresAt: 0, scope: [] });

async function errorOf(r: Response) {
  return (await r.json()).error as { type: string; step?: string; nothingDeleted: boolean };
}

Deno.test("[sin base] camino feliz: SnapTrade → RevenueCat → eToro → Binance → auth, sin el uid en los logs", async () => {
  resetEtoroCaches();
  const fake = fakeDb({ snaptrade: snapSecret, etoro: etoroTokens });
  const up = upstreams();
  const lines: string[] = [];
  const original = console.log;
  console.log = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  let r: Response;
  try {
    r = await handle(request(), fakeDeps(fake, up.fetch));
  } finally {
    console.log = original;
  }
  assertEquals(r.status, 200);
  assertEquals(await r.json(), { deleted: true });
  assertEquals(fake.ops, [
    "rpc:rate_limit_hit",
    "rpc:snaptrade_secret_read",
    "rpc:snaptrade_disconnect",
    "rpc:etoro_tokens_read",
    "rpc:etoro_disconnect",
    "rpc:binance_disconnect",
    "auth:deleteUser",
  ]);
  // El último es el segundo DELETE de RevenueCat (paso 6).
  assertEquals(hosts(up.calls), [
    "api.snaptrade.com",
    "api.revenuecat.com",
    "www.etoro.com/revoke",
    "www.etoro.com/revoke",
    "api.revenuecat.com",
  ]);
  const rcCalls = up.calls.filter((c) => c.url.includes("revenuecat"));
  assertEquals(rcCalls.map((c) => c.init?.method), ["DELETE", "DELETE"]);
  const rc = up.calls.find((c) => c.url.includes("revenuecat"))!;
  assertEquals(rc.init?.method, "DELETE");
  assert(rc.url.endsWith(`/v1/subscribers/${UID}`));
  assertEquals((rc.init?.headers as Record<string, string>).Authorization, "Bearer sk_rc_test");
  const st = up.calls.find((c) => c.url.includes("snaptrade"))!;
  assertEquals(st.init?.method, "DELETE");
  assert(st.url.includes("userId=st-user"));
  const logged = lines.join("\n");
  assert(!logged.includes(UID) && !logged.includes("et-access") && !logged.includes("st-secret"));
});

Deno.test("[sin base] errores antes de tocar nada: 405, 401, 400, 429, misconfigured → nothingDeleted", async () => {
  const cases: [Request, Record<string, string>, FakeOpts, number, string][] = [
    [request({}, "jwt", "GET"), env, {}, 405, "method_not_allowed"],
    [request({ confirm: true }, null), env, {}, 401, "unauthorized"],
    [request({ confirm: true }, "otro"), env, {}, 401, "unauthorized"],
    [request({}), env, {}, 400, "invalid_request"],
    [request({ confirm: "true" }), env, {}, 400, "invalid_request"],
    [request("no es json"), env, {}, 400, "invalid_request"],
    [request(), env, { rate: false }, 429, "rate_limited"],
    [request(), { ...env, REVENUECAT_SECRET_API_KEY: "" }, {}, 500, "misconfigured"],
    [request(), { ...env, SNAPTRADE_CONSUMER_KEY: "" }, { snaptrade: snapSecret }, 500, "misconfigured"],
  ];
  for (const [req, e, opts, status, type] of cases) {
    const fake = fakeDb(opts);
    const up = upstreams();
    const r = await handle(req, fakeDeps(fake, up.fetch, e));
    assertEquals(r.status, status, type);
    const err = await errorOf(r);
    assertEquals([err.type, err.nothingDeleted], [type, true]);
    assertEquals(up.calls.length, 0, type);
    assert(!fake.ops.some((o) => o.endsWith("_disconnect") || o === "auth:deleteUser"), type);
  }
  // 401: ni siquiera toca la base (compliance §6.1).
  const fake = fakeDb();
  await handle(request({ confirm: true }, null), fakeDeps(fake, upstreams().fetch));
  assertEquals(fake.ops, []);
  // Sin SnapTrade conectado, no hacen falta sus credenciales.
  const noSnap = await handle(request(), fakeDeps(fakeDb(), upstreams().fetch, { REVENUECAT_SECRET_API_KEY: "sk" }));
  assertEquals(noSnap.status, 200);
});

Deno.test("[sin base] SnapTrade caído: 502 snaptrade, nothingDeleted y no sigue", async () => {
  const fake = fakeDb({ snaptrade: snapSecret });
  const up = upstreams({ snaptrade: 500 });
  const r = await handle(request(), fakeDeps(fake, up.fetch));
  assertEquals(r.status, 502);
  assertEquals(await errorOf(r), { type: "upstream_unavailable", message: "SnapTrade unavailable", step: "snaptrade", nothingDeleted: true } as never);
  assertEquals(hosts(up.calls), ["api.snaptrade.com"]);
  assert(!fake.ops.includes("rpc:snaptrade_disconnect"));
});

Deno.test("[sin base] SnapTrade 404 (ya no existía) cuenta como hecho", async () => {
  const r = await handle(request(), fakeDeps(fakeDb({ snaptrade: snapSecret }), upstreams({ snaptrade: 404 }).fetch));
  assertEquals(r.status, 200);
});

Deno.test("[sin base] RevenueCat: reintenta 5xx/429, 404 es ok, otro 4xx corta sin reintentar", async () => {
  // Se recupera al tercer intento (+1: el segundo DELETE del paso 6).
  let up = upstreams({ revenuecat: [503, 429, 200] });
  assertEquals((await handle(request(), fakeDeps(fakeDb(), up.fetch))).status, 200);
  assertEquals(up.calls.filter((c) => c.url.includes("revenuecat")).length, 4);

  // 404: el cliente ya no existía.
  assertEquals((await handle(request(), fakeDeps(fakeDb(), upstreams({ revenuecat: 404 }).fetch))).status, 200);

  // 401 (clave inválida): corta en el primer intento. Sin SnapTrade → nada borrado.
  up = upstreams({ revenuecat: 401 });
  const fake = fakeDb();
  let r = await handle(request(), fakeDeps(fake, up.fetch));
  assertEquals(r.status, 502);
  let err = await errorOf(r);
  assertEquals([err.type, err.step, err.nothingDeleted], ["upstream_unavailable", "revenuecat", true]);
  assertEquals(up.calls.length, 1);
  assert(!fake.ops.includes("auth:deleteUser"));

  // Siempre caído, después de borrar SnapTrade: nothingDeleted false.
  up = upstreams({ revenuecat: 503 });
  r = await handle(request(), fakeDeps(fakeDb({ snaptrade: snapSecret }), up.fetch));
  assertEquals(r.status, 502);
  err = await errorOf(r);
  assertEquals([err.step, err.nothingDeleted], ["revenuecat", false]);
  assertEquals(up.calls.filter((c) => c.url.includes("revenuecat")).length, 3);
});

Deno.test("[sin base] eToro: la revocación es best effort; sin credenciales no revoca pero desconecta", async () => {
  resetEtoroCaches();
  let fake = fakeDb({ etoro: etoroTokens });
  let up = upstreams({ etoro: 500 });
  assertEquals((await handle(request(), fakeDeps(fake, up.fetch))).status, 200);
  assert(fake.ops.includes("rpc:etoro_disconnect"));

  fake = fakeDb({ etoro: etoroTokens });
  up = upstreams();
  const { ETORO_CLIENT_SECRET: _drop, ...noEtoro } = env;
  assertEquals((await handle(request(), fakeDeps(fake, up.fetch, noEtoro))).status, 200);
  assertEquals(up.calls.filter((c) => c.url.includes("etoro")).length, 0);
  assert(fake.ops.includes("rpc:etoro_disconnect"));
});

Deno.test("[sin base] errores de base en etoro, binance y auth: delete_failed con su step y nothingDeleted false", async () => {
  const boom = { message: "boom" };
  for (const [opts, step] of [
    [{ rpcErrors: { etoro_tokens_read: boom } }, "etoro"],
    [{ rpcErrors: { etoro_disconnect: boom } }, "etoro"],
    [{ rpcErrors: { binance_disconnect: boom } }, "binance"],
    [{ deleteUserError: { message: "boom", status: 500 } }, "auth"],
  ] as [FakeOpts, string][]) {
    const r = await handle(request(), fakeDeps(fakeDb(opts), upstreams().fetch));
    assertEquals(r.status, 500, step);
    const err = await errorOf(r);
    // RevenueCat ya borró al cliente en esta llamada.
    assertEquals([err.type, err.step, err.nothingDeleted], ["delete_failed", step, false], step);
  }
});

Deno.test("[sin base] usuario ya borrado: deleteUser 404 o FK del rate limit → 200 deleted", async () => {
  const notFound = { message: "User not found", status: 404, code: "user_not_found" };
  let r = await handle(request(), fakeDeps(fakeDb({ deleteUserError: notFound }), upstreams({ revenuecat: 404 }).fetch));
  assertEquals([r.status, await r.json()], [200, { deleted: true }]);

  // Se perdió la respuesta del borrado y el JWT (asimétrico) sigue validando.
  const fake = fakeDb({ rpcErrors: { rate_limit_hit: { message: "fk", code: "23503" } } });
  const up = upstreams();
  r = await handle(request(), fakeDeps(fake, up.fetch));
  assertEquals([r.status, await r.json()], [200, { deleted: true }]);
  assertEquals(up.calls.length, 0);
  assertEquals(fake.ops, ["rpc:rate_limit_hit"]);

  // Otro error del rate limit: no arranca.
  r = await handle(request(), fakeDeps(fakeDb({ rpcErrors: { rate_limit_hit: { message: "down" } } }), upstreams().fetch));
  assertEquals(r.status, 500);
  assertEquals((await errorOf(r)).nothingDeleted, true);
});

Deno.test("[sin base] paso 6: el segundo DELETE de RevenueCat se hace siempre y su falla no cambia el 200", async () => {
  for (const second of [500, 429, 404]) {
    const up = upstreams({ revenuecat: [200, second] });
    const lines: string[] = [];
    const original = console.log;
    console.log = (...a: unknown[]) => lines.push(a.map(String).join(" "));
    let r: Response;
    try {
      r = await handle(request(), fakeDeps(fakeDb(), up.fetch));
    } finally {
      console.log = original;
    }
    assertEquals([r.status, await r.json()], [200, { deleted: true }], String(second));
    // Sin reintentos: exactamente 2 llamadas.
    assertEquals(up.calls.filter((c) => c.url.includes("revenuecat")).length, 2, String(second));
    assertEquals(lines.some((l) => l.includes("revenuecat_recheck_failed")), second !== 404, String(second));
  }
  // Red caída en el segundo DELETE: también 200.
  let n = 0;
  const flaky = fakeFetch((url) => {
    if (url.includes("revenuecat") && ++n === 2) throw new Error("network");
    return new Response("{}", { status: 200 });
  });
  assertEquals((await handle(request(), fakeDeps(fakeDb(), flaky.fetch))).status, 200);
  // Si deleteUser falla, no hay paso 6.
  const up = upstreams();
  await handle(request(), fakeDeps(fakeDb({ deleteUserError: { message: "boom", status: 500 } }), up.fetch));
  assertEquals(up.calls.filter((c) => c.url.includes("revenuecat")).length, 1);
});

Deno.test("[sin base] secreto de SnapTrade ilegible: no traba el borrado", async () => {
  const fake = fakeDb({ snaptrade: "{roto" });
  const up = upstreams();
  assertEquals((await handle(request(), fakeDeps(fake, up.fetch))).status, 200);
  assertEquals(up.calls.filter((c) => c.url.includes("snaptrade")).length, 0);
  assert(fake.ops.includes("rpc:snaptrade_disconnect"));
});

// ---------------------------------------------------------------------------
// Contra el stack local
// ---------------------------------------------------------------------------

/// Usuario con SnapTrade, eToro y Binance conectados y una posición de cada uno.
async function connectedUser() {
  const user = await createUser("premium");
  for (const [fn, payload] of [
    ["snaptrade_secret_save", snapSecret],
    ["etoro_tokens_save", etoroTokens],
    ["binance_keys_save", JSON.stringify({ api_key: "k", api_secret: "s" })],
  ]) {
    const { error } = await db.rpc(fn, { p_user_id: user.id, p_payload: payload });
    if (error) throw error;
  }
  for (const source of ["manual", "etoro", "binance", "snaptrade"]) {
    const { error } = await db.from("positions").insert({
      id: crypto.randomUUID(),
      user_id: user.id,
      ticker: "AAPL",
      quantity: 1,
      purchase_price: 100,
      purchase_date: new Date().toISOString(),
      source,
      external_id: source === "manual" ? null : `${source}-1`,
    });
    if (error) throw error;
  }
  return user;
}

async function rowsOf(userId: string, table: string) {
  const { count, error } = await db.from(table).select("*", { count: "exact", head: true }).eq("user_id", userId);
  if (error) throw error;
  return count ?? 0;
}

const userTables = ["positions", "user_subscriptions", "snaptrade_users", "etoro_tokens", "binance_keys", "api_rate_limits"];

Deno.test("borrado real: borra auth.users, las tablas y los secretos; el reintento con el JWT viejo no rompe", async () => {
  resetEtoroCaches();
  const user = await connectedUser();
  const up = upstreams();
  const d = deps(up.fetch, env);
  const r = await handle(request({ confirm: true }, user.jwt), d);
  assertEquals([r.status, await r.json()], [200, { deleted: true }]);
  const { data } = await db.auth.admin.getUserById(user.id);
  assertEquals(data.user, null);
  for (const t of userTables) assertEquals(await rowsOf(user.id, t), 0, t);
  for (const fn of ["snaptrade_secret_read", "etoro_tokens_read", "binance_keys_read"]) {
    assertEquals((await db.rpc(fn, { p_user_id: user.id })).data, null, fn);
  }
  // Paso 2 y paso 6.
  assertEquals(hosts(up.calls).filter((h) => h === "api.revenuecat.com").length, 2);

  // Reintento: con getUser (clave legacy del stack local) el JWT ya no vale → 401;
  // con getClaims (asimétrico) seguiría validando → 200 por la FK del rate limit.
  const again = await handle(request({ confirm: true }, user.jwt), deps(upstreams().fetch, env));
  assert([200, 401].includes(again.status));
});

Deno.test("corte en RevenueCat y reintento: la cartera queda como manual y el segundo intento termina", async () => {
  const user = await connectedUser();
  const first = await handle(request({ confirm: true }, user.jwt), deps(upstreams({ revenuecat: 503 }).fetch, env));
  assertEquals(first.status, 502);
  const err = await errorOf(first);
  assertEquals([err.step, err.nothingDeleted], ["revenuecat", false]);
  // SnapTrade quedó desconectado (sus posiciones pasan a manual); el resto intacto.
  assertEquals((await db.rpc("snaptrade_secret_read", { p_user_id: user.id })).data, null);
  assertEquals(typeof (await db.rpc("etoro_tokens_read", { p_user_id: user.id })).data, "string");
  assertEquals(await rowsOf(user.id, "positions"), 4);
  const { data: sources } = await db.from("positions").select("source").eq("user_id", user.id);
  assertEquals(sources?.filter((p) => p.source === "snaptrade").length, 0);

  const up = upstreams();
  const second = await handle(request({ confirm: true }, user.jwt), deps(up.fetch, env));
  assertEquals(second.status, 200);
  // SnapTrade ya no se llama: el paso 1 es un no-op.
  assertEquals(up.calls.filter((c) => c.url.includes("snaptrade")).length, 0);
  assertEquals((await db.auth.admin.getUserById(user.id)).data.user, null);
});

Deno.test("doble tap: dos llamadas a la vez terminan bien y el usuario queda borrado", async () => {
  const user = await connectedUser();
  const d = deps(upstreams().fetch, env);
  const results = await Promise.all([
    handle(request({ confirm: true }, user.jwt), d),
    handle(request({ confirm: true }, user.jwt), d),
  ]);
  const statuses = results.map((r) => r.status);
  for (const r of results) await r.body?.cancel();
  assert(statuses.includes(200), String(statuses));
  assert(statuses.every((s) => s === 200 || s === 401), String(statuses));
  assertEquals((await db.auth.admin.getUserById(user.id)).data.user, null);
});

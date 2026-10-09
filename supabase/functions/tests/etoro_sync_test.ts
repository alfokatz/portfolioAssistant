// etoro-sync de punta a punta SIN red ni base: eToro falso (SSO + API) por
// `fetch` y un store en memoria con la misma semántica que las RPCs de
// 20261009000000_etoro_sync.sql (la parte SQL la cubre
// supabase/tests/etoro_sync_db_test.sql).
//
//   deno test --allow-env tests/etoro_sync_test.ts

import { assert, assertEquals, assertFalse, assertMatch } from "jsr:@std/assert@1";
import type { Deps } from "../_shared/common.ts";
import { type EtoroTokens, resetEtoroCaches } from "../etoro-sync/etoro.ts";
import { handle } from "../etoro-sync/handler.ts";
import type { InstrumentMeta } from "../etoro-sync/mapping.ts";
import type { ApplySync, Connection, EtoroStore, OAuthState } from "../etoro-sync/store.ts";
import { stableUuid, syncConfig } from "../etoro-sync/sync.ts";
import { FakeEtoro } from "./etoro_fakes.ts";

const env = {
  ETORO_CLIENT_ID: "porty-client",
  ETORO_CLIENT_SECRET: "porty-secret",
  ETORO_REDIRECT_URI: "https://proj.supabase.co/functions/v1/etoro-sync/callback",
};

// ── store en memoria ────────────────────────────────────────────────────────

type Row = Record<string, unknown> & { source: "manual" | "etoro"; ticker: string; external_id?: string | null };

class MemoryStore implements EtoroStore {
  tiers = new Map<string, string>();
  states = new Map<string, OAuthState>();
  connections = new Map<string, Connection & { lastErrorType?: string | null }>();
  tokens = new Map<string, EtoroTokens>();
  locks = new Set<string>();
  instruments = new Map<number, InstrumentMeta>();
  positions = new Map<string, Row[]>();
  closed = new Map<string, Row[]>();
  tokenSaves = 0;

  effectiveTier(u: string) {
    return Promise.resolve(this.tiers.get(u) ?? "free");
  }
  rateLimitHit() {
    return Promise.resolve(true);
  }
  saveOAuthState(s: OAuthState) {
    this.states.set(s.state, s);
    return Promise.resolve();
  }
  takeOAuthState(state: string) {
    const s = this.states.get(state) ?? null;
    this.states.delete(state);
    return Promise.resolve(s);
  }
  getConnection(u: string) {
    return Promise.resolve(this.connections.get(u) ?? null);
  }
  upsertConnected(u: string, sub: string, scopes: string[]) {
    const prev = this.connections.get(u);
    this.connections.set(u, {
      userId: u,
      etoroSub: sub,
      status: "connected",
      grantedScopes: scopes,
      lastSyncAt: prev?.lastSyncAt ?? null,
      lastResult: prev?.lastResult ?? null,
      historySyncedUntil: prev?.historySyncedUntil ?? null,
    });
    return Promise.resolve();
  }
  markReconnectRequired(u: string) {
    const c = this.connections.get(u);
    if (c) c.status = "reconnect_required";
    return Promise.resolve();
  }
  markSyncError(u: string, type: string) {
    const c = this.connections.get(u);
    if (c) c.lastErrorType = type;
    return Promise.resolve();
  }
  saveTokens(u: string, t: EtoroTokens) {
    this.tokenSaves++;
    this.tokens.set(u, structuredClone(t));
    return Promise.resolve();
  }
  readTokens(u: string) {
    const t = this.tokens.get(u);
    return Promise.resolve(t ? structuredClone(t) : null);
  }
  tryLock(u: string) {
    if (this.locks.has(u)) return Promise.resolve(false);
    this.locks.add(u);
    return Promise.resolve(true);
  }
  unlock(u: string) {
    this.locks.delete(u);
    return Promise.resolve();
  }
  getInstruments(ids: number[]) {
    return Promise.resolve(new Map(ids.filter((i) => this.instruments.has(i)).map((i) => [i, this.instruments.get(i)!])));
  }
  saveInstruments(items: InstrumentMeta[]) {
    for (const i of items) this.instruments.set(i.instrumentId, i);
    return Promise.resolve();
  }
  manualOpenTickers(u: string) {
    return Promise.resolve((this.positions.get(u) ?? []).filter((r) => r.source === "manual").map((r) => r.ticker));
  }
  applySync(u: string, d: ApplySync) {
    const manual = (this.positions.get(u) ?? []).filter((r) => r.source === "manual");
    this.positions.set(u, [
      ...manual,
      ...d.open.map((r) => ({ id: r.id, ticker: r.ticker, quantity: r.quantity, purchase_price: r.purchasePrice, source: "etoro" as const, external_id: r.externalId })),
    ]);
    const closed = this.closed.get(u) ?? [];
    for (const r of d.closed) {
      if (closed.some((c) => c.source === "etoro" && c.external_id === r.externalId)) continue;
      closed.push({ id: r.id, ticker: r.ticker, quantity: r.quantity, realized_pnl: r.realizedPnl, source: "etoro", external_id: r.externalId });
    }
    this.closed.set(u, closed);
    const c = this.connections.get(u)!;
    c.status = "connected";
    c.lastSyncAt = d.result.syncedAt;
    c.lastResult = d.result;
    c.historySyncedUntil = d.historyUntil;
    c.lastErrorType = null;
    return Promise.resolve();
  }
  disconnect(u: string, keep: boolean) {
    let open = 0;
    let closedCount = 0;
    const conv = (rows: Row[]) =>
      keep
        ? rows.map((r) => (r.source === "etoro" ? { ...r, source: "manual" as const, external_id: null } : r))
        : rows.filter((r) => r.source !== "etoro");
    open = (this.positions.get(u) ?? []).filter((r) => r.source === "etoro").length;
    closedCount = (this.closed.get(u) ?? []).filter((r) => r.source === "etoro").length;
    this.positions.set(u, conv(this.positions.get(u) ?? []));
    this.closed.set(u, conv(this.closed.get(u) ?? []));
    this.tokens.delete(u);
    const c = this.connections.get(u);
    if (c) {
      c.status = "disconnected";
      c.lastResult = null;
      c.historySyncedUntil = null;
    }
    return Promise.resolve({ open, closed: closedCount });
  }
}

// ── helpers ─────────────────────────────────────────────────────────────────

function makeDeps(fake: FakeEtoro, nowRef = { t: Date.now() }): Deps & { nowRef: { t: number } } {
  return {
    // deno-lint-ignore no-explicit-any
    db: null as any,
    authenticate: (jwt) => Promise.resolve(jwt.startsWith("jwt-") ? jwt.slice(4) : null),
    fetch: fake.fetch as typeof fetch,
    env: (n) => (env as Record<string, string>)[n],
    now: () => nowRef.t,
    background: () => {},
    nowRef,
  };
}

function post(path: string, user: string | null, body?: unknown): Request {
  return new Request(`http://local/functions/v1/etoro-sync${path}`, {
    method: "POST",
    headers: { ...(user ? { Authorization: `Bearer jwt-${user}` } : {}), "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

async function connect(store: MemoryStore, fake: FakeEtoro, deps: Deps, user = "u1"): Promise<Response> {
  const start = await handle(post("/connect/start", user), deps, () => store);
  assertEquals(start.status, 200);
  const authorizeUrl = new URL((await start.json()).authorizeUrl);
  fake.nonce = authorizeUrl.searchParams.get("nonce")!;
  const state = authorizeUrl.searchParams.get("state")!;
  return await handle(
    new Request(`http://local/functions/v1/etoro-sync/callback?code=good-code&state=${state}`),
    deps,
    () => store,
  );
}

function setup(tier = "premium") {
  resetEtoroCaches();
  const store = new MemoryStore();
  store.tiers.set("u1", tier);
  const fake = new FakeEtoro();
  const deps = makeDeps(fake);
  return { store, fake, deps };
}

/// Lo que se loguea durante [fn] (para chequear que no salen tokens).
async function captureLogs(fn: () => Promise<unknown>): Promise<string> {
  const lines: string[] = [];
  const log = console.log;
  const err = console.error;
  console.log = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  console.error = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  try {
    await fn();
  } finally {
    console.log = log;
    console.error = err;
  }
  return lines.join("\n");
}

// ── conectar ────────────────────────────────────────────────────────────────

Deno.test("sin JWT → 401; sin configurar → 503", async () => {
  const { store, deps } = setup();
  assertEquals((await handle(post("/sync", null), deps, () => store)).status, 401);
  const noEnv = { ...deps, env: () => undefined };
  const r = await handle(post("/sync", "u1"), noEnv, () => store);
  assertEquals(r.status, 503);
  assertEquals((await r.json()).error.type, "etoro_not_configured");
});

Deno.test("plan Free → 403 etoro_plan_required (Premium y Gold sí)", async () => {
  const { store, deps } = setup("free");
  const r = await handle(post("/connect/start", "u1"), deps, () => store);
  assertEquals(r.status, 403);
  assertEquals((await r.json()).error.type, "etoro_plan_required");
  store.tiers.set("u1", "gold");
  assertEquals((await handle(post("/connect/start", "u1"), deps, () => store)).status, 200);
});

Deno.test("connect/start: URL de eToro con PKCE S256, state, nonce y SOLO scopes de lectura", async () => {
  const { store, deps } = setup();
  const r = await handle(post("/connect/start", "u1"), deps, () => store);
  const url = new URL((await r.json()).authorizeUrl);
  assertEquals(url.origin + url.pathname, "https://www.etoro.com/sso");
  assertEquals(url.searchParams.get("response_type"), "code");
  assertEquals(url.searchParams.get("client_id"), "porty-client");
  assertEquals(url.searchParams.get("code_challenge_method"), "S256");
  assertEquals(url.searchParams.get("scope"), "openid etoro-public:real:read");
  assertFalse(/write/.test(url.searchParams.get("scope")!));
  const state = store.states.get(url.searchParams.get("state")!)!;
  assertEquals(state.userId, "u1");
  // El verifier nunca sale del servidor: en la URL solo va su hash.
  assertFalse(url.toString().includes(state.codeVerifier));
});

Deno.test("callback ok: guarda tokens, importa y vuelve a la app sin tokens en el deep link", async () => {
  const { store, fake, deps } = setup();
  const r = await connect(store, fake, deps);
  assertEquals(r.status, 302);
  const location = r.headers.get("location")!;
  assertEquals(location, "porty-etoro://callback?status=ok");

  const conn = store.connections.get("u1")!;
  assertEquals(conn.status, "connected");
  assertEquals(conn.etoroSub, "pairwise-sub-1");
  assertEquals(conn.grantedScopes, ["openid", "etoro-public:real:read"]);
  assert(store.tokens.get("u1")!.accessToken.startsWith("at-"));

  const rows = store.positions.get("u1")!;
  assertEquals(rows.map((x) => [x.ticker, x.quantity]), [["AAPL", 10], ["AAPL", 5], ["VOO", 0.5]]);
  assertEquals(conn.lastResult!.imported, 3);
  assertEquals(conn.lastResult!.closedImported, 1);
  assertEquals(
    conn.lastResult!.notImported.map((n) => n.reason).sort(),
    ["copy_trading", "leveraged"],
  );
  assertEquals(store.closed.get("u1")![0].realized_pnl, 38.5);

  // Contra la API de eToro, solo GET.
  assert(fake.apiCalls().length > 0);
  assert(fake.apiCalls().every((c) => c.method === "GET"));
  assert(fake.apiCalls().every((c) => c.headers.get("x-request-id")));
  // El state es de un solo uso.
  assertEquals(store.states.size, 0);
});

Deno.test("callback: si eToro concede un scope de escritura, se revoca todo y no se guarda nada", async () => {
  const { store, fake, deps } = setup();
  fake.grantedScope = "openid etoro-public:real:read etoro-public:real:write";
  const r = await connect(store, fake, deps);
  assertEquals(r.headers.get("location"), "porty-etoro://callback?status=error&reason=write_scope");
  assertEquals(store.tokens.size, 0);
  assertEquals(store.connections.size, 0);
  const revokes = fake.calls.filter((c) => c.url.endsWith("/token/revoke"));
  assertEquals(revokes.length, 2);
  assertEquals(fake.validAccess.size + fake.validRefresh.size, 0);
});

Deno.test("callback: falta el scope de lectura → missing_scope", async () => {
  const { store, fake, deps } = setup();
  fake.grantedScope = "openid";
  const r = await connect(store, fake, deps);
  assertEquals(r.headers.get("location"), "porty-etoro://callback?status=error&reason=missing_scope");
  assertEquals(store.tokens.size, 0);
});

Deno.test("callback: ID token con otro nonce → falla cerrado, sin guardar nada", async () => {
  const { store, fake, deps } = setup();
  const start = await handle(post("/connect/start", "u1"), deps, () => store);
  const url = new URL((await start.json()).authorizeUrl);
  fake.nonce = "otro-nonce";
  const r = await handle(
    new Request(`http://local/functions/v1/etoro-sync/callback?code=good-code&state=${url.searchParams.get("state")}`),
    deps,
    () => store,
  );
  assertEquals(r.headers.get("location"), "porty-etoro://callback?status=error&reason=failed");
  assertEquals(store.tokens.size, 0);
});

Deno.test("callback: state reusado, vencido o el usuario canceló", async () => {
  const { store, fake, deps } = setup();
  const start = await handle(post("/connect/start", "u1"), deps, () => store);
  const url = new URL((await start.json()).authorizeUrl);
  fake.nonce = url.searchParams.get("nonce")!;
  const state = url.searchParams.get("state")!;
  const cb = (q: string) => handle(new Request(`http://local/functions/v1/etoro-sync/callback?${q}`), deps, () => store);

  assertEquals((await cb(`error=access_denied&state=${state}`)).headers.get("location"), "porty-etoro://callback?status=cancelled");
  // El state ya se consumió.
  assertEquals((await cb(`code=good-code&state=${state}`)).headers.get("location"), "porty-etoro://callback?status=error&reason=expired");
  assertEquals((await cb("code=good-code")).headers.get("location"), "porty-etoro://callback?status=error&reason=invalid_state");

  const start2 = await handle(post("/connect/start", "u1"), deps, () => store);
  const state2 = new URL((await start2.json()).authorizeUrl).searchParams.get("state")!;
  deps.nowRef.t += 11 * 60 * 1000;
  assertEquals((await cb(`code=good-code&state=${state2}`)).headers.get("location"), "porty-etoro://callback?status=error&reason=expired");
});

// ── sincronizar ─────────────────────────────────────────────────────────────

Deno.test("sync dentro de los 5 minutos → devuelve lo último sin llamar a eToro", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  const before = fake.calls.length;
  deps.nowRef.t += 60 * 1000;
  const r = await handle(post("/sync", "u1"), deps, () => store);
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.throttled, true);
  assertEquals(body.result.imported, 3);
  assertEquals(fake.calls.length, before);
});

Deno.test("sync: posición cerrada en eToro desaparece; las manuales no se tocan; posibles duplicados", async () => {
  const { store, fake, deps } = setup();
  store.positions.set("u1", [{ id: "m1", ticker: "AAPL", quantity: 3, source: "manual" }]);
  await connect(store, fake, deps);
  assertEquals(store.connections.get("u1")!.lastResult!.possibleDuplicates, ["AAPL"]);

  fake.positions = fake.positions.filter((p) => p.positionID !== 12);
  deps.nowRef.t += syncConfig.minIntervalMs + 1;
  const r = await handle(post("/sync", "u1"), deps, () => store);
  assertEquals(r.status, 200);
  const rows = store.positions.get("u1")!;
  assertEquals(rows.filter((x) => x.source === "manual").map((x) => x.id), ["m1"]);
  assertEquals(rows.filter((x) => x.source === "etoro").map((x) => x.external_id), ["11", "13"]);
  // El historial repetido no duplica cerradas.
  assertEquals(store.closed.get("u1")!.length, 1);
});

Deno.test("ids estables: la misma posición de eToro conserva su id entre sincronizaciones", async () => {
  assertEquals(await stableUuid("u1", "open", "11"), await stableUuid("u1", "open", "11"));
  assert(await stableUuid("u1", "open", "11") !== await stableUuid("u2", "open", "11"));
  assertMatch(await stableUuid("u1", "open", "11"), /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

Deno.test("token vencido: refresca, guarda el refresh token NUEVO (rotación) y sigue", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  const oldRefresh = store.tokens.get("u1")!.refreshToken;
  deps.nowRef.t += 2 * 60 * 60 * 1000; // pasó la hora del access token
  const r = await handle(post("/sync", "u1"), deps, () => store);
  assertEquals(r.status, 200);
  const t = store.tokens.get("u1")!;
  assert(t.refreshToken !== oldRefresh);
  assert(fake.validRefresh.has(t.refreshToken!));
  assertFalse(fake.validRefresh.has(oldRefresh!));
});

Deno.test("401 de la API con token 'vigente': un refresco y un reintento", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  fake.validAccess.clear(); // eToro invalidó el access token antes de tiempo
  deps.nowRef.t += syncConfig.minIntervalMs + 1;
  const r = await handle(post("/sync", "u1"), deps, () => store);
  assertEquals(r.status, 200);
  assertEquals(store.connections.get("u1")!.status, "connected");
});

Deno.test("refresh token revocado desde eToro → reconnect_required, sin borrar lo importado", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  fake.refreshInvalid = true;
  deps.nowRef.t += 2 * 60 * 60 * 1000;
  const r = await handle(post("/sync", "u1"), deps, () => store);
  assertEquals(r.status, 409);
  assertEquals((await r.json()).error.type, "etoro_reconnect_required");
  assertEquals(store.connections.get("u1")!.status, "reconnect_required");
  assertEquals(store.positions.get("u1")!.length, 3);
  // Mientras siga así, no se reintenta contra eToro.
  const before = fake.calls.length;
  const again = await handle(post("/sync", "u1"), deps, () => store);
  assertEquals((await again.json()).error.type, "etoro_reconnect_required");
  assertEquals(fake.calls.length, before);
  assertEquals(store.locks.size, 0);
});

Deno.test("reconectar después de reconnect_required vuelve a connected sobre el mismo usuario", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  store.connections.get("u1")!.status = "reconnect_required";
  fake.refreshInvalid = false;
  const r = await connect(store, fake, deps);
  assertEquals(r.headers.get("location"), "porty-etoro://callback?status=ok");
  assertEquals(store.connections.get("u1")!.status, "connected");
});

Deno.test("otra cuenta de eToro al reconectar: lo importado de la anterior se reemplaza", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  fake.sub = "pairwise-sub-2";
  fake.positions = [fake.positions[2]];
  await connect(store, fake, deps);
  assertEquals(store.connections.get("u1")!.etoroSub, "pairwise-sub-2");
  assertEquals(store.positions.get("u1")!.map((x) => x.ticker), ["VOO"]);
});

Deno.test("429 de eToro → 429 con retryAfter; la conexión sigue conectada", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  fake.apiStatus = 429;
  deps.nowRef.t += syncConfig.minIntervalMs + 1;
  const r = await handle(post("/sync", "u1"), deps, () => store);
  assertEquals(r.status, 429);
  const body = await r.json();
  assertEquals(body.error.type, "etoro_rate_limited");
  assertEquals(body.error.retryAfterSeconds, 30);
  assertEquals(store.connections.get("u1")!.status, "connected");
  assertEquals(store.locks.size, 0);
});

Deno.test("5xx de eToro → 503 etoro_unavailable, sin tocar lo importado", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  fake.apiStatus = 502;
  deps.nowRef.t += syncConfig.minIntervalMs + 1;
  const r = await handle(post("/sync", "u1"), deps, () => store);
  assertEquals(r.status, 503);
  assertEquals(store.positions.get("u1")!.length, 3);
});

Deno.test("dos sincronizaciones a la vez → la segunda espera (409 sync_in_progress)", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  deps.nowRef.t += syncConfig.minIntervalMs + 1;
  store.locks.add("u1");
  const r = await handle(post("/sync", "u1"), deps, () => store);
  assertEquals((await r.json()).error.type, "etoro_sync_in_progress");
});

Deno.test("sin conectar → 409 etoro_not_connected", async () => {
  const { store, deps } = setup();
  const r = await handle(post("/sync", "u1"), deps, () => store);
  assertEquals((await r.json()).error.type, "etoro_not_connected");
});

// ── desconectar ─────────────────────────────────────────────────────────────

Deno.test("desconectar conservando: revoca en eToro, borra tokens y las importadas pasan a manuales", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  const r = await handle(post("/disconnect", "u1", { keepAsManual: true }), deps, () => store);
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.keptAsManual, true);
  assertEquals(body.revoked, true);
  assertEquals(store.tokens.size, 0);
  assertEquals(fake.validRefresh.size, 0);
  assert(store.positions.get("u1")!.every((x) => x.source === "manual"));
  assertEquals(store.positions.get("u1")!.length, 3);
  assertEquals(store.connections.get("u1")!.status, "disconnected");
});

Deno.test("desconectar borrando: solo se van las importadas", async () => {
  const { store, fake, deps } = setup();
  store.positions.set("u1", [{ id: "m1", ticker: "MSFT", quantity: 1, source: "manual" }]);
  await connect(store, fake, deps);
  const r = await handle(post("/disconnect", "u1", { keepAsManual: false }), deps, () => store);
  assertEquals(r.status, 200);
  assertEquals(store.positions.get("u1")!.map((x) => x.id), ["m1"]);
  assertEquals(store.closed.get("u1")!.length, 0);
});

Deno.test("desconectar sin decir qué hacer con las posiciones → 400", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  assertEquals((await handle(post("/disconnect", "u1", {}), deps, () => store)).status, 400);
  assertEquals(store.connections.get("u1")!.status, "connected");
});

Deno.test("desconectar aunque eToro no responda al revocar: igual se borra todo de nuestro lado", async () => {
  const { store, fake, deps } = setup();
  await connect(store, fake, deps);
  const failing = { ...deps, fetch: (() => Promise.reject(new Error("offline"))) as typeof fetch };
  resetEtoroCaches();
  const r = await handle(post("/disconnect", "u1", { keepAsManual: false }), failing, () => store);
  assertEquals(r.status, 200);
  assertEquals((await r.json()).revoked, false);
  assertEquals(store.tokens.size, 0);
});

// ── seguridad ───────────────────────────────────────────────────────────────

Deno.test("ningún log ni respuesta incluye tokens, códigos o el client secret", async () => {
  const { store, fake, deps } = setup();
  let responses = "";
  const logs = await captureLogs(async () => {
    const r1 = await connect(store, fake, deps);
    responses += r1.headers.get("location");
    deps.nowRef.t += 2 * 60 * 60 * 1000;
    const r2 = await handle(post("/sync", "u1"), deps, () => store);
    responses += await r2.text();
    fake.refreshInvalid = true;
    deps.nowRef.t += 2 * 60 * 60 * 1000;
    const r3 = await handle(post("/sync", "u1"), deps, () => store);
    responses += await r3.text();
  });
  const all = logs + responses;
  for (const secret of ["at-", "rt-", "good-code", "porty-secret", "u1"]) {
    assertFalse(all.includes(secret), `se filtró "${secret}"`);
  }
});

// ── staging con cuenta demo ─────────────────────────────────────────────────

Deno.test("ETORO_ENVIRONMENT=demo: pide demo:read y lee los endpoints demo (nunca los reales)", async () => {
  const { store, fake, deps } = setup();
  const demoDeps = { ...deps, env: (n: string) => (n === "ETORO_ENVIRONMENT" ? "demo" : (env as Record<string, string>)[n]) };
  fake.grantedScope = "openid etoro-public:demo:read";
  const start = await handle(post("/connect/start", "u1"), demoDeps, () => store);
  const url = new URL((await start.json()).authorizeUrl);
  assertEquals(url.searchParams.get("scope"), "openid etoro-public:demo:read");
  fake.nonce = url.searchParams.get("nonce")!;
  const r = await handle(
    new Request(`http://local/functions/v1/etoro-sync/callback?code=good-code&state=${url.searchParams.get("state")}`),
    demoDeps,
    () => store,
  );
  assertEquals(r.headers.get("location"), "porty-etoro://callback?status=ok");
  const paths = fake.apiCalls().map((c) => new URL(c.url).pathname);
  assert(paths.includes("/api/v1/trading/info/demo/pnl"));
  assert(paths.includes("/api/v1/trading/info/trade/demo/history"));
  assertFalse(paths.some((p) => p.includes("/real/") || p === "/api/v1/trading/info/trade/history"));
  assertEquals(store.positions.get("u1")!.length, 3);
});

Deno.test("en producción (real), un token solo con demo:read se rechaza", async () => {
  const { store, fake, deps } = setup();
  fake.grantedScope = "openid etoro-public:demo:read";
  const r = await connect(store, fake, deps);
  assertEquals(r.headers.get("location"), "porty-etoro://callback?status=error&reason=missing_scope");
});

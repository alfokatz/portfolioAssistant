// snaptrade-sync SIN red ni base: SnapTrade falso por `fetch` y store en
// memoria. La parte SQL la cubre supabase/tests/snaptrade_sync_db_test.sql.
//
//   deno test --allow-env tests/snaptrade_sync_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import type { Deps } from "../_shared/common.ts";
import { handle } from "../snaptrade-sync/handler.ts";
import { mapPositions, portyTicker, selectBrokerages } from "../snaptrade-sync/mapping.ts";
import { type Authorization, type RawPosition, signature, type SnaptradeUser } from "../snaptrade-sync/snaptrade.ts";
import type { BrokerageSummary } from "../snaptrade-sync/mapping.ts";
import type { PositionRow, SnaptradeConnection, SnaptradeStore } from "../snaptrade-sync/store.ts";

// Vectores sacados del SDK oficial (snaptrade-typescript-sdk 13.1.14) con
// la misma clave, el mismo reloj y un adapter de axios que captura el
// header `Signature`.
Deno.test("firma: igual a la del SDK oficial (con body y sin body)", async () => {
  const key = "consumer/key+with=chars";
  const query = "clientId=PORTY-TEST&userId=u-1&userSecret=s-1&timestamp=1761900000";
  assertEquals(
    await signature(key, "/snapTrade/login", query, {
      immediateRedirect: true,
      customRedirect: "porty-snaptrade://callback",
      connectionType: "read",
      showCloseButton: true,
      darkMode: false,
    }),
    "9kklOQ/oQL0cqPa+CMKi95Wshebm256EmKoXdtXnCgM=",
  );
  assertEquals(await signature(key, "/accounts", query, null), "jYLV9IOaTuaeCPmL7dMZaUmf55VZ1syHZJGhOfs1rOU=");
});

const auth = (over: Partial<Authorization>): Authorization => ({
  id: "auth-1",
  name: "Interactive Brokers",
  slug: "INTERACTIVE-BROKERS-FLEX",
  type: "read",
  disabled: false,
  createdAt: "2026-10-01T00:00:00Z",
  url: null,
  ...over,
});

Deno.test("brókers: Premium importa el más viejo; eToro/Binance van directo; trade no", () => {
  const auths = [
    auth({ id: "auth-schwab", name: "Schwab", slug: "SCHWAB", createdAt: "2026-10-05T00:00:00Z" }),
    auth({ id: "auth-ibkr", createdAt: "2026-10-01T00:00:00Z" }),
    auth({ id: "auth-etoro", name: "eToro", slug: "ETORO", createdAt: "2026-09-01T00:00:00Z" }),
    auth({ id: "auth-trade", name: "Webull", slug: "WEBULL", type: "trade", createdAt: "2026-09-02T00:00:00Z" }),
  ];
  const premium = selectBrokerages(auths, 1);
  assertEquals(premium.map((b) => [b.id, b.imported, b.reason]), [
    ["auth-etoro", false, "direct_connection"],
    ["auth-trade", false, "trade_permissions"],
    ["auth-ibkr", true, undefined],
    ["auth-schwab", false, "plan_limit"],
  ]);
  assertEquals(selectBrokerages(auths, null).filter((b) => b.imported).map((b) => b.id), ["auth-ibkr", "auth-schwab"]);
});

const raw = (over: Partial<RawPosition>): RawPosition => ({
  kind: "stock",
  symbol: "AAPL",
  rawSymbol: "AAPL",
  description: null,
  units: 10,
  price: 200,
  costBasis: 150,
  currency: "USD",
  cashEquivalent: false,
  ...over,
});

Deno.test("posiciones: acciones, ETF y cripto entran; efectivo, opciones y cortos no", () => {
  const { holdings, skipped } = mapPositions([
    raw({}),
    raw({ kind: "etf", symbol: "VAB.TO", rawSymbol: "VAB", costBasis: null, price: 25 }),
    raw({ kind: "crypto", symbol: "BTC", rawSymbol: "BTC", units: 0.5, price: 60000, costBasis: 40000 }),
    raw({ kind: "mutualfund", symbol: "SPAXX", cashEquivalent: true }),
    raw({ kind: "cash", symbol: "", rawSymbol: "", currency: "USD" }),
    raw({ kind: "option", symbol: "AAPL 261120C00200000" }),
    raw({ symbol: "TSLA", units: -3 }),
    raw({ symbol: "ZERO", units: 0 }),
    raw({ symbol: "NOPE", price: null, costBasis: null }),
  ]);
  assertEquals(holdings, [
    { ticker: "AAPL", quantity: 10, cost: 150, price: 200 },
    { ticker: "VAB.TO", quantity: 10, cost: null, price: 25 },
    { ticker: "BTC-USD", quantity: 0.5, cost: 40000, price: 60000 },
  ]);
  assertEquals(skipped, [
    { ticker: "SPAXX", reason: "cash" },
    { ticker: "USD", reason: "cash" },
    { ticker: "AAPL 261120C00200000", reason: "unsupported" },
    { ticker: "TSLA", reason: "short" },
    { ticker: "NOPE", reason: "no_price" },
  ]);
  assertEquals(portyTicker(raw({ kind: "crypto", symbol: "eth-usd" })), "ETH-USD");
});

// ── Handler ──

class MemoryStore implements SnaptradeStore {
  tier = "premium";
  connection: SnaptradeConnection | null = null;
  user: SnaptradeUser | null = null;
  applied: PositionRow[] | null = null;
  brokerages: BrokerageSummary[] | null = null;
  errors: string[] = [];
  disconnected: boolean | null = null;
  refreshesLeft = 2;

  effectiveTier() {
    return Promise.resolve(this.tier);
  }
  rateLimitHit() {
    return Promise.resolve(true);
  }
  getConnection() {
    return Promise.resolve(this.connection);
  }
  upsertPending(_u: string, reset: boolean) {
    if (!this.connection || this.connection.status === "disconnected" || reset) {
      this.connection = { status: "pending", lastSyncAt: null, lastResult: null };
    }
    return Promise.resolve();
  }
  saveUser(_u: string, user: SnaptradeUser) {
    this.user = user;
    return Promise.resolve();
  }
  readUser() {
    return Promise.resolve(this.user);
  }
  deleteUser() {
    this.user = null;
    return Promise.resolve();
  }
  tryLock() {
    return Promise.resolve(true);
  }
  unlock() {
    return Promise.resolve();
  }
  takeRefresh() {
    if (this.refreshesLeft <= 0) return Promise.resolve(false);
    this.refreshesLeft--;
    return Promise.resolve(true);
  }
  applySync(_u: string, positions: PositionRow[], brokerages: BrokerageSummary[], result: Record<string, unknown>) {
    this.applied = positions;
    this.brokerages = brokerages;
    this.connection = {
      status: brokerages.length ? "connected" : "pending",
      lastSyncAt: new Date(now).toISOString(),
      lastResult: result,
    };
    return Promise.resolve();
  }
  markError(_u: string, type: string, reconnect: boolean) {
    this.errors.push(type);
    if (reconnect && this.connection) this.connection = { ...this.connection, status: "reconnect_required" };
    return Promise.resolve();
  }
  disconnect(_u: string, keep: boolean) {
    this.disconnected = keep;
    this.user = null;
    return Promise.resolve({ open: 2 });
  }
}

const now = Date.parse("2026-10-31T12:00:00Z");
const env = { SNAPTRADE_CLIENT_ID: "PORTY", SNAPTRADE_CONSUMER_KEY: "secret-key" };

type Call = { method: string; path: string; query: URLSearchParams; body: unknown; signed: boolean };

function fakeSnaptrade(opts: {
  authorizations?: Record<string, unknown>[];
  status?: Record<string, number>;
} = {}) {
  const calls: Call[] = [];
  const authorizations = opts.authorizations ?? [
    {
      id: "auth-ibkr",
      type: "read",
      disabled: false,
      created_date: "2026-10-01T00:00:00Z",
      brokerage: {
        slug: "INTERACTIVE-BROKERS-FLEX",
        display_name: "Interactive Brokers",
        url: "https://www.interactivebrokers.com",
      },
    },
    {
      id: "auth-schwab",
      type: "read",
      disabled: false,
      created_date: "2026-10-05T00:00:00Z",
      brokerage: { slug: "SCHWAB", display_name: "Schwab" },
    },
  ];
  const respond = (input: string, init?: RequestInit): Response => {
    const url = new URL(String(input));
    const body = typeof init?.body === "string" ? JSON.parse(init.body) : null;
    calls.push({
      method: init?.method ?? "GET",
      path: url.pathname,
      query: url.searchParams,
      body,
      signed: Boolean(new Headers(init?.headers).get("Signature")),
    });
    const forced = opts.status?.[url.pathname];
    if (forced) return new Response("{}", { status: forced });
    switch (url.pathname) {
      case "/snapTrade/registerUser":
        return Response.json({ userId: body.userId, userSecret: "fresh-secret" });
      case "/snapTrade/login":
        return Response.json({ redirectURI: "https://app.snaptrade.com/portal?x=1", sessionId: "s" });
      case "/snapTrade/deleteUser":
        return Response.json({ status: "deleted" });
      case "/authorizations":
        return Response.json(authorizations);
      case "/accounts":
        return Response.json([
          {
            id: "acc-ibkr",
            brokerage_authorization: "auth-ibkr",
            name: "IBKR",
            institution_name: "Interactive Brokers",
          },
          { id: "acc-schwab", brokerage_authorization: "auth-schwab", name: "Schwab", institution_name: "Schwab" },
        ]);
      case "/accounts/acc-ibkr/positions/all":
        return Response.json({
          results: [
            {
              instrument: { kind: "stock", symbol: "AAPL", raw_symbol: "AAPL" },
              units: "4",
              price: "200",
              cost_basis: "100",
            },
            {
              instrument: { kind: "stock", symbol: "AAPL", raw_symbol: "AAPL" },
              units: "6",
              price: "200",
              cost_basis: "150",
            },
            {
              instrument: { kind: "etf", symbol: "VOO", raw_symbol: "VOO" },
              units: "2",
              price: "500",
              cost_basis: null,
            },
            { instrument: { kind: "cash", id: "usd" }, units: "1000", currency: "USD" },
          ],
          data_freshness: {},
        });
      case "/accounts/acc-schwab/positions/all":
        return Response.json({
          results: [{ instrument: { kind: "stock", symbol: "MSFT" }, units: "1", price: "400", cost_basis: "300" }],
        });
      default:
        if (url.pathname.endsWith("/refresh")) return Response.json({ detail: "queued" });
        if (url.pathname.startsWith("/authorizations/")) return Response.json({ detail: "deleted" });
        return new Response("not found", { status: 404 });
    }
  };
  const fetchImpl = ((input: string, init?: RequestInit) => Promise.resolve(respond(input, init))) as typeof fetch;
  return { fetchImpl, calls };
}

function deps(fetchImpl: typeof fetch, extraEnv: Record<string, string> = {}): Deps {
  const all: Record<string, string> = { ...env, ...extraEnv };
  return {
    db: null as unknown as Deps["db"],
    authenticate: (jwt) => Promise.resolve(jwt === "ok" ? "user-1" : null),
    fetch: fetchImpl,
    env: (name) => all[name],
    now: () => now,
    background: () => {},
  };
}

const post = (route: string, body: unknown = {}, jwt = "ok") =>
  new Request(`http://local/functions/v1/snaptrade-sync${route}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

const run = (req: Request, store: MemoryStore, fetchImpl: typeof fetch, extraEnv: Record<string, string> = {}) =>
  handle(req, deps(fetchImpl, extraEnv), () => store, () => "st-user-uuid");

Deno.test("conectar: la primera vez crea el usuario con un id propio y abre el portal de solo lectura", async () => {
  const store = new MemoryStore();
  const { fetchImpl, calls } = fakeSnaptrade();
  const res = await run(post("/connect", { darkMode: true }), store, fetchImpl);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { portalUrl: "https://app.snaptrade.com/portal?x=1" });
  assertEquals(store.user, { userId: "st-user-uuid", userSecret: "fresh-secret" });
  assertEquals(store.connection?.status, "pending");
  const login = calls.find((c) => c.path === "/snapTrade/login")!;
  assertEquals(login.body, {
    connectionType: "read",
    immediateRedirect: true,
    customRedirect: "porty-snaptrade://callback",
    darkMode: true,
    showCloseButton: true,
  });
  assertEquals(login.query.get("userSecret"), "fresh-secret");
  assert(calls.every((c) => c.signed && c.query.get("clientId") === "PORTY"));
});

Deno.test("conectar: plan, configuración y JWT", async () => {
  const { fetchImpl, calls } = fakeSnaptrade();
  const free = new MemoryStore();
  free.tier = "free";
  const res = await run(post("/connect"), free, fetchImpl);
  assertEquals(res.status, 403);
  assertEquals((await res.json()).error.type, "snaptrade_plan_required");
  assertEquals(calls.length, 0);

  const unconfigured = await handle(post("/connect"), { ...deps(fetchImpl), env: () => undefined }, () => free);
  assertEquals((await unconfigured.json()).error.type, "snaptrade_not_configured");
  assertEquals((await run(post("/sync", {}, "bad"), free, fetchImpl)).status, 401);
});

Deno.test("conectar: Premium con un bróker ya conectado no puede sumar otro; Gold sí", async () => {
  const oneBroker = [{
    id: "auth-ibkr",
    type: "read",
    created_date: "2026-10-01T00:00:00Z",
    brokerage: { slug: "INTERACTIVE-BROKERS-FLEX", display_name: "Interactive Brokers" },
  }];
  const premium = new MemoryStore();
  premium.user = { userId: "st-1", userSecret: "s" };
  premium.connection = { status: "connected", lastSyncAt: null, lastResult: null };
  const { fetchImpl } = fakeSnaptrade({ authorizations: oneBroker });
  const res = await run(post("/connect"), premium, fetchImpl);
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error.type, "snaptrade_connection_limit");

  // Reconectar el mismo bróker caído sí se puede.
  const again = await run(post("/connect", { reconnect: "auth-ibkr" }), premium, fetchImpl);
  assertEquals(again.status, 200);

  const gold = new MemoryStore();
  gold.tier = "gold";
  gold.user = { userId: "st-1", userSecret: "s" };
  gold.connection = { status: "connected", lastSyncAt: null, lastResult: null };
  assertEquals((await run(post("/connect"), gold, fetchImpl)).status, 200);
});

Deno.test("conectar: si había que reconectar, borra el usuario viejo en SnapTrade y crea otro", async () => {
  const store = new MemoryStore();
  store.user = { userId: "st-old", userSecret: "old" };
  store.connection = { status: "reconnect_required", lastSyncAt: null, lastResult: null };
  const { fetchImpl, calls } = fakeSnaptrade();
  assertEquals((await run(post("/connect"), store, fetchImpl)).status, 200);
  const deleted = calls.find((c) => c.path === "/snapTrade/deleteUser")!;
  assertEquals(deleted.query.get("userId"), "st-old");
  assertEquals(store.user, { userId: "st-user-uuid", userSecret: "fresh-secret" });
  assertEquals(store.connection?.status, "pending");
});

Deno.test("sincronizar Premium: solo el primer bróker, lotes sumados, costo estimado avisado", async () => {
  const store = new MemoryStore();
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = { status: "pending", lastSyncAt: null, lastResult: null };
  const { fetchImpl, calls } = fakeSnaptrade();
  const res = await run(post("/sync"), store, fetchImpl);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.throttled, false);
  assertEquals(body.result.imported, 2);
  assertEquals(body.result.estimatedCost, ["VOO"]);
  assertEquals(body.result.notImported, [{ ticker: "USD", reason: "cash", broker: "Interactive Brokers" }]);
  assertEquals(store.applied?.map((p) => [p.external_id, p.quantity, p.purchase_price, p.broker_price]), [
    ["acc-ibkr:AAPL", 10, 130, 200],
    ["acc-ibkr:VOO", 2, 500, 500],
  ]);
  assertEquals(store.brokerages?.map((b) => [b.name, b.imported, b.reason, b.url]), [
    ["Interactive Brokers", true, undefined, "https://www.interactivebrokers.com"],
    ["Schwab", false, "plan_limit", null],
  ]);
  // La cuenta de Schwab ni se consulta.
  assert(!calls.some((c) => c.path === "/accounts/acc-schwab/positions/all"));
  assertEquals(store.connection?.status, "connected");
});

Deno.test("sincronizar Gold: todos los brókers", async () => {
  const store = new MemoryStore();
  store.tier = "gold";
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = { status: "connected", lastSyncAt: null, lastResult: null };
  const { fetchImpl } = fakeSnaptrade();
  await run(post("/sync"), store, fetchImpl);
  assertEquals(store.applied?.map((p) => p.external_id), ["acc-ibkr:AAPL", "acc-ibkr:VOO", "acc-schwab:MSFT"]);
});

Deno.test("sincronizar: la última si fue hace menos de 5 min; secreto inválido pide reconectar", async () => {
  const store = new MemoryStore();
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = {
    status: "connected",
    lastSyncAt: new Date(now - 60_000).toISOString(),
    lastResult: { imported: 3 },
  };
  const ok = fakeSnaptrade();
  assertEquals(await (await run(post("/sync"), store, ok.fetchImpl)).json(), {
    result: { imported: 3 },
    throttled: true,
  });
  assertEquals(ok.calls.length, 0);
  // Al volver del portal, la app la pide forzada.
  assertEquals((await (await run(post("/sync", { force: true }), store, ok.fetchImpl)).json()).throttled, false);

  store.connection = { status: "connected", lastSyncAt: null, lastResult: null };
  const revoked = fakeSnaptrade({ status: { "/authorizations": 401 } });
  const res = await run(post("/sync"), store, revoked.fetchImpl);
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error.type, "snaptrade_reconnect_required");
  assertEquals(store.connection?.status, "reconnect_required");

  const down = new MemoryStore();
  down.user = store.user;
  down.connection = { status: "connected", lastSyncAt: null, lastResult: null };
  const res503 = await run(post("/sync"), down, fakeSnaptrade({ status: { "/accounts": 502 } }).fetchImpl);
  assertEquals((await res503.json()).error.type, "snaptrade_unavailable");
  assertEquals(down.connection?.status, "connected");
});

Deno.test("actualizar ahora: solo Gold, solo si está habilitado y con cupo diario", async () => {
  const { fetchImpl, calls } = fakeSnaptrade();
  const premium = new MemoryStore();
  premium.user = { userId: "st-1", userSecret: "s" };
  const p = await run(post("/refresh"), premium, fetchImpl, { SNAPTRADE_MANUAL_REFRESH: "on" });
  assertEquals((await p.json()).error.type, "snaptrade_refresh_plan_required");

  const gold = new MemoryStore();
  gold.tier = "gold";
  gold.user = { userId: "st-1", userSecret: "s" };
  const off = await run(post("/refresh"), gold, fetchImpl);
  assertEquals((await off.json()).error.type, "snaptrade_refresh_unavailable");

  gold.refreshesLeft = 1;
  const on = await run(post("/refresh"), gold, fetchImpl, { SNAPTRADE_MANUAL_REFRESH: "on" });
  assertEquals(await on.json(), { queued: 2 });
  assertEquals(calls.filter((c) => c.path.endsWith("/refresh")).map((c) => c.path), [
    "/authorizations/auth-ibkr/refresh",
    "/authorizations/auth-schwab/refresh",
  ]);
  const limit = await run(post("/refresh"), gold, fetchImpl, { SNAPTRADE_MANUAL_REFRESH: "on" });
  assertEquals(limit.status, 429);
  assertEquals((await limit.json()).error.type, "snaptrade_refresh_limit");
});

Deno.test("quitar un bróker: lo borra en SnapTrade y vuelve a sincronizar", async () => {
  const store = new MemoryStore();
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = { status: "connected", lastSyncAt: new Date(now).toISOString(), lastResult: { imported: 1 } };
  const { fetchImpl, calls } = fakeSnaptrade();
  assertEquals((await run(post("/remove", {}), store, fetchImpl)).status, 400);
  const res = await run(post("/remove", { authorizationId: "auth-ibkr" }), store, fetchImpl);
  assertEquals(res.status, 200);
  assert(calls.some((c) => c.method === "DELETE" && c.path === "/authorizations/auth-ibkr"));
  // Forzada: no devuelve la de hace un rato.
  assertEquals((await res.json()).throttled, false);
});

Deno.test("desconectar: exige la decisión, borra el usuario en SnapTrade (también en Free)", async () => {
  const store = new MemoryStore();
  store.tier = "free";
  store.user = { userId: "st-1", userSecret: "s" };
  const { fetchImpl, calls } = fakeSnaptrade();
  assertEquals((await run(post("/disconnect", {}), store, fetchImpl)).status, 400);
  const res = await run(post("/disconnect", { keepAsManual: true }), store, fetchImpl);
  assertEquals(await res.json(), { open: 2, keptAsManual: true });
  assertEquals(calls.find((c) => c.path === "/snapTrade/deleteUser")?.query.get("userId"), "st-1");
  assertEquals(store.disconnected, true);
});

Deno.test("desconectar: si SnapTrade no responde, no se desconecta (seguiría cobrándose)", async () => {
  const store = new MemoryStore();
  store.user = { userId: "st-1", userSecret: "s" };
  const { fetchImpl } = fakeSnaptrade({ status: { "/snapTrade/deleteUser": 500 } });
  const res = await run(post("/disconnect", { keepAsManual: false }), store, fetchImpl);
  assertEquals(res.status, 503);
  assertEquals(store.disconnected, null);
  assert(store.user);
});

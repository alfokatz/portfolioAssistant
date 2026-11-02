// snaptrade-sync SIN red ni base: SnapTrade falso por `fetch` y store en
// memoria. La parte SQL la cubre supabase/tests/snaptrade_sync_db_test.sql.
//
//   deno test --allow-env tests/snaptrade_sync_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import type { Deps } from "../_shared/common.ts";
import { handle } from "../snaptrade-sync/handler.ts";
import { lotsFor, type Trade } from "../snaptrade-sync/lots.ts";
import {
  type DirectBroker,
  directBrokerOf,
  mapPositions,
  portyTicker,
  selectBrokerages,
} from "../snaptrade-sync/mapping.ts";
import { type Authorization, type RawPosition, signature, type SnaptradeUser } from "../snaptrade-sync/snaptrade.ts";
import type { BrokerageSummary } from "../snaptrade-sync/mapping.ts";
import type { ClosedRow, PositionRow, SnaptradeConnection, SnaptradeStore } from "../snaptrade-sync/store.ts";

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

Deno.test("brókers: Premium importa el más viejo; eToro conectado directo no se duplica; trade no", () => {
  const auths = [
    auth({ id: "auth-schwab", name: "Schwab", slug: "SCHWAB", createdAt: "2026-10-05T00:00:00Z" }),
    auth({ id: "auth-ibkr", createdAt: "2026-10-01T00:00:00Z" }),
    auth({ id: "auth-etoro", name: "eToro", slug: "ETORO", createdAt: "2026-09-01T00:00:00Z" }),
    auth({ id: "auth-trade", name: "Webull", slug: "WEBULL", type: "trade", createdAt: "2026-09-02T00:00:00Z" }),
  ];
  // Ya tiene eToro conectado directo en Porty: por SnapTrade no entra.
  const premium = selectBrokerages(auths, 1, new Set(["etoro"]));
  assertEquals(premium.map((b) => [b.id, b.imported, b.reason]), [
    ["auth-etoro", false, "direct_connection"],
    ["auth-trade", false, "trade_permissions"],
    ["auth-ibkr", true, undefined],
    ["auth-schwab", false, "plan_limit"],
  ]);
  assertEquals(selectBrokerages(auths, null, new Set(["etoro"])).filter((b) => b.imported).map((b) => b.id), [
    "auth-ibkr",
    "auth-schwab",
  ]);
  // Sin la directa, eToro entra por SnapTrade como cualquier bróker (y
  // ocupa el lugar de Premium: es el más viejo).
  assertEquals(selectBrokerages(auths, 1).map((b) => [b.id, b.imported, b.reason]), [
    ["auth-etoro", true, undefined],
    ["auth-trade", false, "trade_permissions"],
    ["auth-ibkr", false, "plan_limit"],
    ["auth-schwab", false, "plan_limit"],
  ]);
  assertEquals(directBrokerOf({ slug: "BINANCE-US", name: "Binance US" }), "binance");
  assertEquals(directBrokerOf({ slug: "SCHWAB", name: "Schwab" }), null);
});

const trade = (id: string, type: string, units: number, price: number, date: string, fee = 0): Trade => ({
  id,
  type,
  ticker: "VOO",
  units,
  price,
  fee,
  date,
});

Deno.test("compras: FIFO con ventas, la venta cerrada con su costo y lo que el historial no explica", () => {
  const trades = [
    trade("b1", "BUY", 1, 400, "2024-02-05"),
    trade("b2", "BUY", 1, 450, "2024-03-05", 1),
    trade("b3", "BUY", 1, 500, "2024-04-05"),
    // Vende 1,5: se va la primera entera y media de la segunda.
    trade("s1", "SELL", 1.5, 520, "2024-05-10", 2),
    trade("r1", "REI", 0.1, 510, "2024-06-01"),
  ];
  const { lots, closed } = lotsFor(trades, 1.6, null, 600, "2026-11-02T00:00:00.000Z");
  assertEquals(lots.map((l) => [l.id, Number(l.units.toFixed(6)), Number(l.price.toFixed(2)), l.date]), [
    ["b2", 0.5, 451, "2024-03-05"],
    ["b3", 1, 500, "2024-04-05"],
    ["r1", 0.1, 510, "2024-06-01"],
  ]);
  assertEquals(closed.length, 1);
  assertEquals(closed[0].units, 1.5);
  // 1 a 400 + 0,5 a 451 (la comisión de compra va al costo).
  assertEquals(Number(closed[0].avgPurchasePrice.toFixed(4)), Number(((400 + 0.5 * 451) / 1.5).toFixed(4)));
  assertEquals(Number(closed[0].realizedPnl.toFixed(2)), Number(((520 - (400 + 225.5) / 1.5) * 1.5 - 2).toFixed(2)));

  // Tiene 3 pero el historial explica 1,6 (transfirió desde otro bróker):
  // la diferencia va como una compra estimada que cierra el costo del bróker.
  const more = lotsFor(trades, 3, 480, 600, "2026-11-02T00:00:00.000Z");
  const rest = more.lots[0];
  assertEquals([rest.id, rest.estimated, Number(rest.units.toFixed(6))], ["rest", true, 1.4]);
  const total = more.lots.reduce((sum, l) => sum + l.units * l.price, 0);
  assertEquals(Number(total.toFixed(4)), Number((480 * 3).toFixed(4)));

  // Tiene menos de lo que explica (vendió algo fuera del historial): se
  // recortan las más viejas.
  const less = lotsFor(trades, 1, null, 600, "2026-11-02T00:00:00.000Z");
  assertEquals(less.lots.map((l) => [l.id, Number(l.units.toFixed(6))]), [["b3", 0.9], ["r1", 0.1]]);

  // Sin historial: una sola compra estimada al costo del bróker.
  assertEquals(lotsFor([], 2, 500, 600, "2026-11-02T00:00:00.000Z").lots, [
    { id: "rest", units: 2, price: 500, date: "2026-11-02T00:00:00.000Z", estimated: true },
  ]);
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
  taxLots: [],
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
    { ticker: "AAPL", quantity: 10, cost: 150, price: 200, taxLots: [] },
    { ticker: "VAB.TO", quantity: 10, cost: null, price: 25, taxLots: [] },
    { ticker: "BTC-USD", quantity: 0.5, cost: 40000, price: 60000, taxLots: [] },
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
  closed: ClosedRow[] | null = null;
  brokerages: BrokerageSummary[] | null = null;
  errors: string[] = [];
  disconnected: boolean | null = null;
  refreshesLeft = 2;
  direct = new Set<DirectBroker>();

  effectiveTier() {
    return Promise.resolve(this.tier);
  }
  rateLimitHit() {
    return Promise.resolve(true);
  }
  getConnection() {
    return Promise.resolve(this.connection);
  }
  directConnections() {
    return Promise.resolve(this.direct);
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
  applySync(
    _u: string,
    positions: PositionRow[],
    closed: ClosedRow[],
    brokerages: BrokerageSummary[],
    result: Record<string, unknown>,
  ) {
    this.applied = positions;
    this.closed = closed;
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
        if (url.pathname.endsWith("/refresh") || url.pathname.endsWith("/transactions/sync")) {
          return Response.json({ detail: "queued" });
        }
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
    ["acc-ibkr:AAPL:rest", 10, 130, 200],
    ["acc-ibkr:VOO:rest", 2, 500, 500],
  ]);
  assertEquals(store.brokerages?.map((b) => [b.name, b.imported, b.reason, b.url]), [
    ["Interactive Brokers", true, undefined, "https://www.interactivebrokers.com"],
    ["Schwab", false, "plan_limit", null],
  ]);
  // La cuenta de Schwab ni se consulta.
  assert(!calls.some((c) => c.path === "/accounts/acc-schwab/positions/all"));
  assertEquals(store.connection?.status, "connected");
});

Deno.test("sincronizar: eToro por SnapTrade entra si no está conectado directo; si lo está, no", async () => {
  const etoroOnly = [{
    id: "auth-etoro",
    type: "read",
    created_date: "2026-11-01T00:00:00Z",
    brokerage: { slug: "ETORO", display_name: "eToro" },
  }];
  const accounts = (fetchImpl: typeof fetch) =>
    ((input: string, init?: RequestInit) => {
      const path = new URL(String(input)).pathname;
      if (path === "/accounts") {
        return Promise.resolve(
          Response.json([{ id: "acc-etoro", brokerage_authorization: "auth-etoro", institution_name: "eToro" }]),
        );
      }
      if (path === "/accounts/acc-etoro/positions/all") {
        return Promise.resolve(Response.json({
          results: [{ instrument: { kind: "stock", symbol: "NVDA" }, units: "3", price: "180", cost_basis: "120" }],
        }));
      }
      return fetchImpl(input, init);
    }) as typeof fetch;

  const store = new MemoryStore();
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = { status: "pending", lastSyncAt: null, lastResult: null };
  const { fetchImpl } = fakeSnaptrade({ authorizations: etoroOnly });
  await run(post("/sync"), store, accounts(fetchImpl));
  assertEquals(store.applied?.map((p) => [p.external_id, p.quantity, p.purchase_price]), [[
    "acc-etoro:NVDA:rest",
    3,
    120,
  ]]);

  // Conectó eToro directo: se quita de SnapTrade y, como era el único,
  // se borra el usuario (deja de cobrarse) y lo importado por acá.
  const both = new MemoryStore();
  both.user = store.user;
  both.connection = { status: "connected", lastSyncAt: null, lastResult: null };
  both.direct = new Set(["etoro"]);
  const calls = fakeSnaptrade({ authorizations: etoroOnly });
  const res = await run(post("/sync"), both, accounts(calls.fetchImpl));
  assertEquals((await res.json()).result.imported, 0);
  assert(calls.calls.some((c) => c.method === "DELETE" && c.path === "/authorizations/auth-etoro"));
  assertEquals(calls.calls.find((c) => c.path === "/snapTrade/deleteUser")?.query.get("userId"), "st-1");
  assertEquals(both.disconnected, false);
  assertEquals(both.applied, null);
});

Deno.test("sincronizar: con eToro directo y otro bróker, solo quita eToro de SnapTrade", async () => {
  const store = new MemoryStore();
  store.tier = "gold";
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = { status: "connected", lastSyncAt: null, lastResult: null };
  store.direct = new Set(["etoro"]);
  const { fetchImpl, calls } = fakeSnaptrade({
    authorizations: [
      {
        id: "auth-ibkr",
        type: "read",
        created_date: "2026-10-01T00:00:00Z",
        brokerage: { slug: "IBKR", name: "IBKR" },
      },
      {
        id: "auth-etoro",
        type: "read",
        created_date: "2026-11-01T00:00:00Z",
        brokerage: { slug: "ETORO", name: "eToro" },
      },
    ],
  });
  await run(post("/sync"), store, fetchImpl);
  assert(calls.some((c) => c.method === "DELETE" && c.path === "/authorizations/auth-etoro"));
  assert(!calls.some((c) => c.path === "/snapTrade/deleteUser"));
  assertEquals(store.brokerages?.map((b) => b.id), ["auth-ibkr"]);
  assertEquals(store.disconnected, null);
});

Deno.test("sincronizar: con el historial, una fila por compra mensual y las ventas como cerradas", async () => {
  const months = ["2024-02-05", "2024-03-05", "2024-04-05", "2024-05-06"];
  const activities = [
    ...months.map((d, i) => ({
      id: `buy-${i}`,
      type: "BUY",
      symbol: { symbol: "VOO", type: { code: "et" } },
      units: 1,
      price: 400 + i * 10,
      fee: 0,
      trade_date: `${d}T14:30:00Z`,
    })),
    {
      id: "sell-0",
      type: "SELL",
      symbol: { symbol: "VOO", type: { code: "et" } },
      units: -1,
      price: 500,
      fee: 0,
      trade_date: "2024-08-01T15:00:00Z",
    },
    // Una opción (sin símbolo de acción): se ignora.
    { id: "opt", type: "BUY", symbol: null, units: 1, price: 2, trade_date: "2024-01-01" },
  ];
  const ibkr = [{
    id: "auth-ibkr",
    type: "read",
    created_date: "2026-10-01T00:00:00Z",
    brokerage: { slug: "IBKR", display_name: "Interactive Brokers" },
  }];
  const base = fakeSnaptrade({ authorizations: ibkr });
  const fetchImpl = ((input: string, init?: RequestInit) => {
    const url = new URL(String(input));
    if (url.pathname === "/accounts") {
      return Promise.resolve(
        Response.json([{ id: "acc", brokerage_authorization: "auth-ibkr", institution_name: "IBKR" }]),
      );
    }
    if (url.pathname === "/accounts/acc/positions/all") {
      return Promise.resolve(Response.json({
        results: [{ instrument: { kind: "etf", symbol: "VOO" }, units: "3", price: "600", cost_basis: "426.67" }],
      }));
    }
    if (url.pathname === "/accounts/acc/activities") {
      assertEquals(url.searchParams.get("type"), "BUY,SELL,REI");
      return Promise.resolve(Response.json({ data: activities, pagination: { offset: 0, limit: 1000, total: 6 } }));
    }
    return base.fetchImpl(input, init);
  }) as typeof fetch;

  const store = new MemoryStore();
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = { status: "pending", lastSyncAt: null, lastResult: null };
  const res = await (await run(post("/sync"), store, fetchImpl)).json();
  assertEquals(res.result.imported, 1);
  assertEquals(store.applied?.map((p) => [p.external_id, p.quantity, p.purchase_price, p.purchase_date]), [
    ["acc:VOO:buy-1", 1, 410, "2024-03-05T14:30:00.000Z"],
    ["acc:VOO:buy-2", 1, 420, "2024-04-05T14:30:00.000Z"],
    ["acc:VOO:buy-3", 1, 430, "2024-05-06T14:30:00.000Z"],
  ]);
  assertEquals(
    store.closed?.map((c) => [c.external_id, c.quantity, c.avg_purchase_price, c.close_price, c.realized_pnl]),
    [
      ["acc:sell-0", 1, 400, 500, 100],
    ],
  );
});

Deno.test("sincronizar: los tax lots del bróker dan cada compra con su fecha", async () => {
  const ibkr = [{
    id: "auth-ibkr",
    type: "read",
    created_date: "2026-10-01T00:00:00Z",
    brokerage: { slug: "IBKR", display_name: "Interactive Brokers" },
  }];
  const base = fakeSnaptrade({ authorizations: ibkr });
  const fetchImpl = ((input: string, init?: RequestInit) => {
    const url = new URL(String(input));
    if (url.pathname === "/accounts") {
      return Promise.resolve(
        Response.json([{ id: "acc", brokerage_authorization: "auth-ibkr", institution_name: "IBKR" }]),
      );
    }
    if (url.pathname === "/accounts/acc/positions/all") {
      return Promise.resolve(Response.json({
        results: [{
          instrument: { kind: "etf", symbol: "VOO" },
          units: "3",
          price: "600",
          cost_basis: "450",
          tax_lots: [
            { lot_id: "L1", quantity: "1", purchased_price: "400", original_purchase_date: "2024-02-05T00:00:00Z" },
            { lot_id: "L2", quantity: "2", purchased_price: "475", original_purchase_date: "2025-06-02T00:00:00Z" },
            // Un lote a medias (sin fecha) no se usa.
            { lot_id: "L3", quantity: "1", purchased_price: "500" },
          ],
        }],
      }));
    }
    if (url.pathname === "/accounts/acc/activities") return Promise.resolve(Response.json({ data: [] }));
    return base.fetchImpl(input, init);
  }) as typeof fetch;
  const store = new MemoryStore();
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = { status: "pending", lastSyncAt: null, lastResult: null };
  await run(post("/sync"), store, fetchImpl);
  assertEquals(
    store.applied?.map((p) => [p.external_id, p.quantity, p.purchase_price, p.purchase_date, p.purchase_date_known]),
    [
      ["acc:VOO:lot-L1", 1, 400, "2024-02-05T00:00:00.000Z", true],
      ["acc:VOO:lot-L2", 2, 475, "2025-06-02T00:00:00.000Z", true],
    ],
  );
});

Deno.test("sincronizar: sin historial, la compra queda con fecha desconocida", async () => {
  const store = new MemoryStore();
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = { status: "pending", lastSyncAt: null, lastResult: null };
  const { fetchImpl } = fakeSnaptrade();
  await run(post("/sync"), store, fetchImpl);
  assert(store.applied!.length > 0);
  assert(store.applied!.every((p) => p.purchase_date_known === false));
});

Deno.test("al volver del portal pide sincronizar las operaciones; en una normal, no", async () => {
  const store = new MemoryStore();
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = { status: "pending", lastSyncAt: null, lastResult: null };
  const forced = fakeSnaptrade();
  await run(post("/sync", { force: true }), store, forced.fetchImpl);
  // Premium: solo el bróker que importa.
  assertEquals(
    forced.calls.filter((c) => c.path.endsWith("/transactions/sync")).map((c) => [c.method, c.path]),
    [["POST", "/authorizations/auth-ibkr/transactions/sync"]],
  );
  const normal = fakeSnaptrade();
  store.connection = { status: "connected", lastSyncAt: null, lastResult: null };
  await run(post("/sync"), store, normal.fetchImpl);
  assert(!normal.calls.some((c) => c.path.endsWith("/transactions/sync")));
});

Deno.test("sincronizar Gold: todos los brókers", async () => {
  const store = new MemoryStore();
  store.tier = "gold";
  store.user = { userId: "st-1", userSecret: "s" };
  store.connection = { status: "connected", lastSyncAt: null, lastResult: null };
  const { fetchImpl } = fakeSnaptrade();
  await run(post("/sync"), store, fetchImpl);
  assertEquals(store.applied?.map((p) => p.external_id), [
    "acc-ibkr:AAPL:rest",
    "acc-ibkr:VOO:rest",
    "acc-schwab:MSFT:rest",
  ]);
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

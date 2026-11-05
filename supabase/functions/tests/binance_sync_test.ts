// binance-sync SIN red ni base: Binance falso por `fetch` y store en
// memoria. La parte SQL la cubre supabase/tests/binance_sync_db_test.sql.
//
//   deno test --allow-env tests/binance_sync_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import type { Deps } from "../_shared/common.ts";
import { type BinanceKeys, hmacHex, type Trade } from "../binance-sync/binance.ts";
import { handle } from "../binance-sync/handler.ts";
import { averageCost, keyProblem, mapBalances, usdPrice } from "../binance-sync/mapping.ts";
import type { BinanceConnection, BinanceStore, PositionRow } from "../binance-sync/store.ts";

Deno.test("firma HMAC-SHA256: el ejemplo de la documentación de Binance", async () => {
  const secret = "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j";
  const query =
    "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559";
  assertEquals(await hmacHex(secret, query), "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71");
});

Deno.test("permisos: solo lectura pasa; operar, retirar o transferir no", () => {
  assertEquals(keyProblem({ enableReading: true, enableWithdrawals: false, enableSpotAndMarginTrading: false }), null);
  assertEquals(keyProblem({ enableReading: true, enableSpotAndMarginTrading: true }), "write_permissions");
  assertEquals(keyProblem({ enableReading: true, enableWithdrawals: true }), "write_permissions");
  assertEquals(keyProblem({ enableReading: true, permitsUniversalTransfer: true }), "write_permissions");
  assertEquals(keyProblem({ enableReading: false }), "no_read");
});

const prices = new Map([
  ["BTCUSDT", 60000],
  ["ETHUSDT", 3000],
  ["LDOUSDT", 2],
  ["SHIBUSDT", 0.00001],
  ["XYZBTC", 0.0001],
]);

Deno.test("saldos: Simple Earn suma al activo, LDO es LDO, efectivo y polvo aparte", () => {
  const { holdings, notImported } = mapBalances([
    { asset: "BTC", free: 0.1, locked: 0 },
    { asset: "LDBTC", free: 0.05, locked: 0 },
    { asset: "ETH", free: 1, locked: 0.5 },
    { asset: "LDO", free: 10, locked: 0 },
    { asset: "USDT", free: 500, locked: 0 },
    { asset: "LDUSDT", free: 20, locked: 0 },
    { asset: "SHIB", free: 1000, locked: 0 },
    { asset: "XYZ", free: 1, locked: 0 },
    { asset: "NOPE", free: 5, locked: 0 },
  ], prices);
  assertEquals(holdings.map((h) => [h.asset, Number(h.quantity.toFixed(8))]), [
    ["BTC", 0.15],
    ["ETH", 1.5],
    ["LDO", 10],
    ["XYZ", 1],
  ]);
  assertEquals(notImported, [
    { asset: "NOPE", reason: "no_price" },
    { asset: "SHIB", reason: "dust" },
    { asset: "USDT", reason: "cash" },
  ]);
  assertEquals(usdPrice("XYZ", prices), 6);
});

const trade = (over: Partial<Trade>): Trade => ({
  price: 100,
  qty: 1,
  commission: 0,
  commissionAsset: "USDT",
  time: 1,
  isBuyer: true,
  ...over,
});

Deno.test("costo promedio: compras, ventas al promedio y comisión en el activo", () => {
  const c = averageCost("ETH", [
    trade({ time: 1, price: 2000, qty: 1 }),
    trade({ time: 2, price: 3000, qty: 1, commission: 0.01, commissionAsset: "ETH" }),
    trade({ time: 3, price: 4000, qty: 0.99, isBuyer: false }),
  ], 1);
  // Compra 1 a 2000 + 0.99 netos a 3000: 1.99 por 5000. Vende 0.99 al
  // promedio: queda 1 con costo 5000 × 1/1.99.
  assert(c);
  assertEquals(Number(c.price.toFixed(4)), Number((5000 / 1.99).toFixed(4)));
  assertEquals(c.openedAt, 1);
});

Deno.test("costo promedio: vendió todo y volvió a comprar; o el historial no alcanza", () => {
  const reopened = averageCost("BTC", [
    trade({ time: 1, price: 10, qty: 1 }),
    trade({ time: 2, price: 20, qty: 1, isBuyer: false }),
    trade({ time: 3, price: 30, qty: 2 }),
  ], 2)!;
  assertEquals(reopened, { price: 30, openedAt: 3 });
  // Tiene 10 pero las operaciones explican 1: no inventa un costo.
  assertEquals(averageCost("BTC", [trade({ qty: 1 })], 10), null);
});

// ── Handler ──

class MemoryStore implements BinanceStore {
  tier = "premium";
  connection: BinanceConnection | null = null;
  keys: BinanceKeys | null = null;
  applied: PositionRow[] | null = null;
  errors: string[] = [];
  disconnected: boolean | null = null;

  effectiveTier() {
    return Promise.resolve(this.tier);
  }
  rateLimitHit() {
    return Promise.resolve(true);
  }
  getConnection() {
    return Promise.resolve(this.connection);
  }
  upsertConnected() {
    this.connection = { status: "connected", lastSyncAt: null, lastResult: null };
    return Promise.resolve();
  }
  saveKeys(_u: string, keys: BinanceKeys) {
    this.keys = keys;
    return Promise.resolve();
  }
  readKeys() {
    return Promise.resolve(this.keys);
  }
  tryLock() {
    return Promise.resolve(true);
  }
  unlock() {
    return Promise.resolve();
  }
  applySync(_u: string, positions: PositionRow[], result: Record<string, unknown>) {
    this.applied = positions;
    this.connection = { status: "connected", lastSyncAt: new Date(now).toISOString(), lastResult: result };
    return Promise.resolve();
  }
  markError(_u: string, type: string, reconnect: boolean) {
    this.errors.push(type);
    if (reconnect && this.connection) this.connection = { ...this.connection, status: "reconnect_required" };
    return Promise.resolve();
  }
  disconnect(_u: string, keep: boolean) {
    this.disconnected = keep;
    this.keys = null;
    return Promise.resolve({ open: 2 });
  }
}

const now = Date.parse("2026-10-16T12:00:00Z");
const apiKey = "A".repeat(64);
const apiSecret = "S".repeat(64);

function fakeBinance(opts: { restrictions?: Record<string, unknown>; accountStatus?: number } = {}) {
  const calls: { url: string; key: string | null }[] = [];
  const fetchImpl = ((input: string, init?: RequestInit) => {
    const url = new URL(String(input));
    calls.push({ url: url.pathname, key: new Headers(init?.headers).get("X-MBX-APIKEY") });
    if (url.pathname === "/sapi/v1/account/apiRestrictions") {
      return Promise.resolve(Response.json(opts.restrictions ?? { enableReading: true }));
    }
    if (url.pathname === "/api/v3/account") {
      if (opts.accountStatus) {
        return Promise.resolve(Response.json({ code: -2015, msg: "Invalid API-key" }, { status: opts.accountStatus }));
      }
      return Promise.resolve(Response.json({
        balances: [
          { asset: "BTC", free: "0.2", locked: "0" },
          { asset: "ETH", free: "0", locked: "0" },
          { asset: "USDT", free: "100", locked: "0" },
        ],
      }));
    }
    if (url.pathname === "/api/v3/ticker/price") {
      return Promise.resolve(Response.json([{ symbol: "BTCUSDT", price: "60000" }]));
    }
    if (url.pathname === "/api/v3/myTrades") {
      assert(url.searchParams.get("signature"));
      return Promise.resolve(Response.json([
        { price: "40000", qty: "0.2", commission: "0", commissionAsset: "USDT", time: 1700000000000, isBuyer: true },
      ]));
    }
    return Promise.resolve(new Response("not found", { status: 404 }));
  }) as typeof fetch;
  return { fetchImpl, calls };
}

function deps(fetchImpl: typeof fetch): Deps {
  return {
    db: null as unknown as Deps["db"],
    authenticate: (jwt) => Promise.resolve(jwt === "ok" ? "user-1" : null),
    fetch: fetchImpl,
    env: () => undefined,
    now: () => now,
    background: () => {},
  };
}

const post = (route: string, body: unknown = {}, jwt = "ok") =>
  new Request(`http://local/functions/v1/binance-sync${route}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

Deno.test("conectar: clave de solo lectura → guarda, importa con el costo promedio", async () => {
  const store = new MemoryStore();
  const { fetchImpl, calls } = fakeBinance();
  const res = await handle(post("/connect", { api_key: apiKey, api_secret: apiSecret }), deps(fetchImpl), () => store);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.result.imported, 1);
  assertEquals(body.result.notImported, [{ asset: "USDT", reason: "cash" }]);
  assertEquals(store.keys, { apiKey, apiSecret });
  assertEquals(store.applied?.map((p) => [p.ticker, p.quantity, p.purchase_price, p.broker_price]), [
    ["BTC-USD", 0.2, 40000, 60000],
  ]);
  assertEquals(store.applied?.[0].purchase_date, new Date(1700000000000).toISOString());
  // Las firmadas llevan la clave en el header; la de precios, no.
  assert(calls.find((c) => c.url === "/api/v3/account")?.key === apiKey);
  assertEquals(calls.find((c) => c.url === "/api/v3/ticker/price")?.key, null);
});

Deno.test("conectar: una clave que puede operar se rechaza sin guardar nada", async () => {
  const store = new MemoryStore();
  const { fetchImpl, calls } = fakeBinance({ restrictions: { enableReading: true, enableSpotAndMarginTrading: true } });
  const res = await handle(post("/connect", { api_key: apiKey, api_secret: apiSecret }), deps(fetchImpl), () => store);
  assertEquals(res.status, 422);
  assertEquals((await res.json()).error.type, "binance_write_permissions");
  assertEquals(store.keys, null);
  assertEquals(calls.map((c) => c.url), ["/sapi/v1/account/apiRestrictions"]);
});

Deno.test("conectar: plan, formato de la clave y JWT", async () => {
  const free = new MemoryStore();
  free.tier = "free";
  const { fetchImpl } = fakeBinance();
  assertEquals(
    (await handle(post("/connect", { api_key: apiKey, api_secret: apiSecret }), deps(fetchImpl), () => free)).status,
    403,
  );
  const store = new MemoryStore();
  const bad = await handle(post("/connect", { api_key: "x", api_secret: apiSecret }), deps(fetchImpl), () => store);
  assertEquals((await bad.json()).error.type, "binance_invalid_key");
  assertEquals((await handle(post("/sync", {}, "bad"), deps(fetchImpl), () => store)).status, 401);
});

Deno.test("sincronizar: la última si fue hace menos de 5 min; clave revocada pide reconectar", async () => {
  const store = new MemoryStore();
  store.keys = { apiKey, apiSecret };
  store.connection = {
    status: "connected",
    lastSyncAt: new Date(now - 60_000).toISOString(),
    lastResult: { imported: 3 },
  };
  const ok = fakeBinance();
  const throttled = await (await handle(post("/sync"), deps(ok.fetchImpl), () => store)).json();
  assertEquals(throttled, { result: { imported: 3 }, throttled: true });
  assertEquals(ok.calls.length, 0);

  store.connection = { status: "connected", lastSyncAt: null, lastResult: null };
  const revoked = fakeBinance({ accountStatus: 401 });
  const res = await handle(post("/sync"), deps(revoked.fetchImpl), () => store);
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error.type, "binance_reconnect_required");
  assertEquals(store.connection?.status, "reconnect_required");
});

Deno.test("desconectar: exige la decisión y borra la clave", async () => {
  const store = new MemoryStore();
  store.keys = { apiKey, apiSecret };
  const { fetchImpl } = fakeBinance();
  assertEquals((await handle(post("/disconnect", {}), deps(fetchImpl), () => store)).status, 400);
  const res = await handle(post("/disconnect", { keepAsManual: true }), deps(fetchImpl), () => store);
  assertEquals(await res.json(), { open: 2, keptAsManual: true });
  assertEquals(store.keys, null);
  assertEquals(store.disconnected, true);
});

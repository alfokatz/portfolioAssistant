// market-watch SIN red ni base: Yahoo/Finnhub falsos por `fetch` y stores
// en memoria. La parte SQL (price_alerts_record, market_enqueue_moves) la
// cubre supabase/tests/push_notifications_db_test.sql.
//
//   deno test --allow-env tests/market_watch_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import { resetSession, yahooSessionConfig } from "../_shared/yahoo_session.ts";
import { type AlertRow, type AlertUpdate, evaluateAlert, thresholdPrice } from "../market-watch/alerts.ts";
import { handle, type MarketDeps, runMarketWatch } from "../market-watch/handler.ts";
import { marketDate, marketPhase } from "../market-watch/market_clock.ts";
import { computeMoves, type Holding, type UserMoves } from "../market-watch/moves.ts";
import { fetchQuotes, parseYahooQuotes, type Quote, quotesConfig } from "../market-watch/quotes.ts";
import type { MarketStore } from "../market-watch/store.ts";
import { FakeSender, MemoryDispatchStore } from "./push_fakes.ts";

// Martes 13/10/2026: 11:00 en Nueva York (EDT, UTC-4).
const tuesday11 = Date.parse("2026-10-13T15:00:00Z");

const alert = (over: Partial<AlertRow> = {}): AlertRow => ({
  id: "a1",
  user_id: "u1",
  symbol: "VOO",
  condition: "above",
  target: 750,
  reference_price: null,
  repeat: "once",
  rearm_ready: true,
  triggered_at: null,
  ...over,
});

const quote = (symbol: string, price: number, prevClose: number, over: Partial<Quote> = {}): Quote => ({
  symbol,
  price,
  prevClose,
  changePct: ((price - prevClose) / prevClose) * 100,
  currency: "USD",
  marketState: "REGULAR",
  quoteType: "EQUITY",
  ...over,
});

// ── reloj ───────────────────────────────────────────────────────────────────

Deno.test("reloj: abierto, apertura y cerrado (incluye fin de semana)", () => {
  assertEquals(marketPhase(tuesday11), "open");
  assertEquals(marketPhase(Date.parse("2026-10-13T13:45:00Z")), "opening"); // 9:45 ET
  assertEquals(marketPhase(Date.parse("2026-10-13T13:00:00Z")), "closed"); // 9:00 ET
  assertEquals(marketPhase(Date.parse("2026-10-13T20:05:00Z")), "open"); // 16:05 ET (cierre)
  assertEquals(marketPhase(Date.parse("2026-10-13T20:30:00Z")), "closed");
  assertEquals(marketPhase(Date.parse("2026-10-17T15:00:00Z")), "closed"); // sábado
  // Diciembre (EST, UTC-5): 9:35 ET = 14:35Z.
  assertEquals(marketPhase(Date.parse("2026-12-08T14:35:00Z")), "opening");
  // 23:00 ET del lunes es martes en UTC, pero el día de mercado es lunes.
  assertEquals(marketDate(Date.parse("2026-10-13T03:00:00Z")), "2026-10-12");
});

// ── alertas ─────────────────────────────────────────────────────────────────

Deno.test("alertas: once dispara al cumplirse", () => {
  assertEquals(evaluateAlert(alert(), 749.9, "2026-10-13", null)?.fire, false);
  const hit = evaluateAlert(alert(), 751.2, "2026-10-13", null)!;
  assertEquals(hit.fire, true);
  assertEquals(hit.price, 751.2);
  assertEquals(hit.fired_on, "2026-10-13");
  assertEquals(evaluateAlert(alert({ condition: "below", target: 500 }), 500, "2026-10-13", null)?.fire, true);
});

Deno.test("alertas: porcentaje contra el precio de referencia", () => {
  const a = alert({ condition: "pct_down", target: 10, reference_price: 180 });
  assertEquals(thresholdPrice(a), 162);
  assertEquals(evaluateAlert(a, 162.5, "d", null)?.fire, false);
  assertEquals(evaluateAlert(a, 161.9, "d", null)?.fire, true);
  assertEquals(evaluateAlert(alert({ condition: "pct_up", target: 5, reference_price: null }), 999, "d", null), null);
});

Deno.test("alertas: daily no repite el mismo día ni sin volver 1% del otro lado", () => {
  const a = alert({ repeat: "daily", target: 100 });
  const first = evaluateAlert(a, 101, "2026-10-13", null)!;
  assertEquals(first.fire, true);
  assertEquals(first.rearm_ready, false);

  // Mismo día, otra vez arriba: no.
  const fired = { ...a, rearm_ready: false, triggered_at: "2026-10-13T15:00:00Z" };
  assertEquals(evaluateAlert(fired, 102, "2026-10-13", "2026-10-13")?.fire, false);
  // Al día siguiente, sin haber vuelto abajo: no.
  assertEquals(evaluateAlert(fired, 101, "2026-10-14", "2026-10-13")?.fire, false);
  // Baja apenas (99.5, dentro del 1%): no rearma.
  assertEquals(evaluateAlert(fired, 99.5, "2026-10-14", "2026-10-13")?.rearm_ready, false);
  // Baja a 98.9: rearma; y la próxima vez que cruza, avisa.
  const back = evaluateAlert(fired, 98.9, "2026-10-14", "2026-10-13")!;
  assertEquals(back.rearm_ready, true);
  assertEquals(back.fire, false);
  assertEquals(evaluateAlert({ ...fired, rearm_ready: true }, 100.5, "2026-10-15", "2026-10-13")?.fire, true);
});

// ── movimientos ─────────────────────────────────────────────────────────────

const holding = (symbol: string, quantity: number, over: Partial<Holding> = {}): Holding => ({
  user_id: "u1",
  symbol,
  quantity,
  sensitivity: "normal",
  big_moves: true,
  portfolio_moves: true,
  ...over,
});

Deno.test("movimientos: umbral por tipo, peso mínimo y nivel 2 al doble", () => {
  const quotes = new Map([
    ["NVDA", quote("NVDA", 94, 100)], // -6% acción, pesa mucho
    ["VOO", quote("VOO", 103.5, 100, { quoteType: "ETF" })], // +3.5% ETF (umbral 3)
    ["TINY", quote("TINY", 120, 100)], // +20% pero pesa < 3%
    ["AMD", quote("AMD", 89, 100)], // -11%: nivel 2
    ["BTC-USD", quote("BTC-USD", 80, 100, { quoteType: "CRYPTOCURRENCY" })], // cripto: fuera (D4)
  ]);
  const [u] = computeMoves(
    [holding("NVDA", 10), holding("VOO", 5), holding("TINY", 0.1), holding("AMD", 3), holding("BTC-USD", 2)],
    quotes,
  );
  const bySymbol = Object.fromEntries(u.moves.map((m) => [m.symbol, m]));
  assertEquals(Object.keys(bySymbol).sort(), ["AMD", "NVDA", "VOO"]);
  assertEquals(bySymbol.NVDA.direction, "down");
  assertEquals(bySymbol.NVDA.level, 1);
  assertEquals(bySymbol.AMD.level, 2);
  assertEquals(bySymbol.VOO.direction, "up");
  // Ordenados por impacto (variación × peso): NVDA primero.
  assertEquals(u.moves[0].symbol, "NVDA");
});

Deno.test("movimientos: sensibilidad baja sube los umbrales", () => {
  const quotes = new Map([["NVDA", quote("NVDA", 94, 100)]]);
  assertEquals(computeMoves([holding("NVDA", 10, { sensitivity: "low", portfolio_moves: false })], quotes), []);
  assertEquals(computeMoves([holding("NVDA", 10, { sensitivity: "high" })], quotes)[0].moves.length, 1);
});

Deno.test("movimientos: la cartera entera, con el S&P y lo que más la movió", () => {
  const quotes = new Map([
    ["NVDA", quote("NVDA", 92, 100)],
    ["MSFT", quote("MSFT", 99, 100)],
    ["KO", quote("KO", 100.5, 100)],
    ["^GSPC", quote("^GSPC", 98, 100, { quoteType: "INDEX" })],
  ]);
  const [u] = computeMoves([holding("NVDA", 5), holding("MSFT", 5, { big_moves: false }), holding("KO", 1)], quotes);
  assert(u.portfolio);
  // (5*92 + 5*99 + 100.5) - (5*100 + 5*100 + 100) = -44.5 sobre 1100.
  assertEquals(u.portfolio.change_pct, -4.05);
  assertEquals(u.portfolio.change_value, -44.5);
  assertEquals(u.portfolio.benchmark_change_pct, -2);
  assertEquals(u.portfolio.moves.map((m) => m.symbol), ["NVDA", "MSFT"]);
});

Deno.test("movimientos: sin precios suficientes no avisa por la cartera", () => {
  const quotes = new Map([["NVDA", quote("NVDA", 90, 100)]]);
  const [u] = computeMoves(
    [holding("NVDA", 1, { big_moves: false }), holding("A", 1), holding("B", 1), holding("C", 1)],
    quotes,
  ) ?? [];
  assertEquals(u, undefined);
});

// ── cotizaciones ────────────────────────────────────────────────────────────

const yahooBody = {
  quoteResponse: {
    result: [
      { symbol: "VOO", regularMarketPrice: 751.2, regularMarketPreviousClose: 740, regularMarketChangePercent: 1.51, marketState: "REGULAR", quoteType: "ETF", currency: "USD" },
      { symbol: "XXX", regularMarketPrice: null },
    ],
    error: null,
  },
};

Deno.test("cotizaciones: parsea Yahoo y descarta lo que no tiene precio", () => {
  const q = parseYahooQuotes(yahooBody);
  assertEquals(q.length, 1);
  assertEquals(q[0].symbol, "VOO");
  assertEquals(q[0].quoteType, "ETF");
  assertEquals(parseYahooQuotes({}), []);
});

function fakeMarket(opts: { yahooStatus?: number; finnhub?: Record<string, number> } = {}) {
  const calls: string[] = [];
  const fetchImpl = ((input: string, init?: RequestInit) => {
    const url = String(input);
    calls.push(url);
    if (url.startsWith(yahooSessionConfig.cookieUrl)) {
      return Promise.resolve(new Response("", { status: 404, headers: { "set-cookie": "A3=abc; Secure" } }));
    }
    if (url.startsWith(yahooSessionConfig.crumbUrl)) {
      return Promise.resolve(new Response(new Headers(init?.headers).get("cookie") ? "crumb1" : "", { status: 200 }));
    }
    if (url.startsWith(quotesConfig.yahooQuoteUrl)) {
      if (opts.yahooStatus && opts.yahooStatus !== 200) return Promise.resolve(new Response("", { status: opts.yahooStatus }));
      const symbols = new URL(url).searchParams.get("symbols")!.split(",");
      return Promise.resolve(Response.json({
        quoteResponse: {
          result: symbols.filter((s) => s !== "MISSING").map((s) => ({
            symbol: s,
            regularMarketPrice: s === "VOO" ? 751.2 : s === "NVDA" ? 93 : 100,
            regularMarketPreviousClose: 100,
            marketState: "REGULAR",
            quoteType: s === "VOO" ? "ETF" : "EQUITY",
          })),
        },
      }));
    }
    if (url.startsWith(quotesConfig.finnhubQuoteUrl)) {
      const s = new URL(url).searchParams.get("symbol")!;
      const c = opts.finnhub?.[s];
      return Promise.resolve(c ? Response.json({ c, pc: c, dp: 0 }) : Response.json({ c: 0 }));
    }
    return Promise.resolve(new Response("", { status: 404 }));
  }) as typeof fetch;
  return { fetchImpl, calls };
}

Deno.test("cotizaciones: lotes de 50 con crumb, y Finnhub solo para lo que falta de las alertas", async () => {
  resetSession();
  const m = fakeMarket({ finnhub: { MISSING: 42 } });
  const symbols = [...Array.from({ length: 60 }, (_, i) => `S${i}`), "MISSING"];
  const quotes = await fetchQuotes(
    { fetch: m.fetchImpl, now: () => tuesday11, env: (k) => (k === "FINNHUB_API_KEY" ? "fk" : undefined) },
    symbols,
    new Set(["MISSING"]),
  );
  assertEquals(quotes.size, 61);
  assertEquals(quotes.get("MISSING")?.price, 42);
  const yahooCalls = m.calls.filter((c) => c.startsWith(quotesConfig.yahooQuoteUrl));
  assertEquals(yahooCalls.length, 2);
  assertEquals(new URL(yahooCalls[0]).searchParams.get("crumb"), "crumb1");
  assertEquals(m.calls.filter((c) => c.startsWith(quotesConfig.finnhubQuoteUrl)).length, 1);
});

// ── corrida completa ────────────────────────────────────────────────────────

class MemoryMarketStore implements MarketStore {
  alerts: AlertRow[] = [];
  holdingRows: Holding[] = [];
  saved: Quote[] = [];
  recorded: AlertUpdate[] = [];
  enqueued: UserMoves[] = [];
  holdingsCalls = 0;

  constructor(private readonly dispatch: MemoryDispatchStore) {}

  activeAlerts() {
    return Promise.resolve(this.alerts);
  }
  holdings() {
    this.holdingsCalls++;
    return Promise.resolve(this.holdingRows);
  }
  saveQuotes(q: Quote[]) {
    this.saved.push(...q);
    return Promise.resolve();
  }
  recordAlerts(updates: AlertUpdate[]) {
    this.recorded.push(...updates);
    const fired = updates.filter((u) => u.fire);
    for (const u of fired) {
      const a = this.alerts.find((x) => x.id === u.id)!;
      this.dispatch.add(a.user_id, "price_alert", { symbol: a.symbol, condition: a.condition, target: a.target, price: u.price });
    }
    return Promise.resolve(fired.length);
  }
  enqueueMoves(_date: string, items: UserMoves[]) {
    this.enqueued.push(...items);
    for (const i of items) {
      for (const m of i.moves) this.dispatch.add(i.user_id, "big_move", m);
    }
    return Promise.resolve(items.reduce((s, i) => s + i.moves.length, 0));
  }
}

function marketDeps(now: number, secret = "s3cret") {
  resetSession();
  const dispatch = new MemoryDispatchStore(() => now);
  dispatch.user("u1", {
    devices: [{ id: "d1", token: "tok-u1", platform: "ios", locale: "es", timezone: "America/New_York" }],
  });
  const store = new MemoryMarketStore(dispatch);
  const sender = new FakeSender();
  const deps: MarketDeps = {
    env: (k) => (k === "CRON_SECRET" ? secret : undefined),
    now: () => now,
    fetch: fakeMarket().fetchImpl,
    store,
    dispatchStore: dispatch,
    sender,
  };
  return { deps, store, dispatch, sender };
}

Deno.test("corrida: dispara la alerta, detecta el movimiento y despacha en el momento", async () => {
  const { deps, store, sender } = marketDeps(tuesday11);
  store.alerts = [alert()];
  store.holdingRows = [holding("NVDA", 10), holding("KO", 1)];
  const r = await runMarketWatch(deps);
  assertEquals(r.alertsFired, 1);
  assertEquals(r.movesQueued, 1);
  assertEquals(r.dispatched, 2);
  assert(store.saved.some((q) => q.symbol === "^GSPC"));
  const titles = sender.sent.map((m) => m.title).sort();
  assertEquals(titles, ["NVDA baja 7.0% hoy", "VOO pasó $750.00"]);
});

Deno.test("corrida: en la primera media hora solo alertas; cerrado, nada", async () => {
  const opening = marketDeps(Date.parse("2026-10-13T13:45:00Z"));
  opening.store.alerts = [alert()];
  opening.store.holdingRows = [holding("NVDA", 10)];
  const r = await runMarketWatch(opening.deps);
  assertEquals(r.alertsFired, 1);
  assertEquals(opening.store.holdingsCalls, 0);
  assertEquals(r.movesQueued, 0);

  const closed = marketDeps(Date.parse("2026-10-17T15:00:00Z"));
  closed.store.alerts = [alert()];
  assertEquals((await runMarketWatch(closed.deps)).skipped, "market_closed");
  assertEquals(closed.store.recorded.length, 0);
});

Deno.test("handler: secreto del cron y force para probar fuera de horario", async () => {
  const { deps, store } = marketDeps(Date.parse("2026-10-17T15:00:00Z"));
  store.alerts = [alert()];
  const req = (secret: string | null, body?: unknown) =>
    new Request("http://local/functions/v1/market-watch", {
      method: "POST",
      headers: secret ? { "x-cron-secret": secret } : {},
      body: body ? JSON.stringify(body) : undefined,
    });
  assertEquals((await handle(req(null), deps)).status, 401);
  assertEquals((await (await handle(req("s3cret"), deps)).json()).skipped, "market_closed");
  const forced = await (await handle(req("s3cret", { force: true }), deps)).json();
  assertEquals(forced.alertsFired, 1);
});

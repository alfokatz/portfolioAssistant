// Noticias por ticker en capas: subyacente de símbolos locales (cualquier
// mercado), presentaciones de la SEC y búsqueda web por ticker bajo demanda
// (capa 4: cuándo se dispara y cuándo no). Base local real (supabase start);
// OpenAI, GDELT y la SEC reemplazados por `fetch` falso.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { handle } from "../daily-brief/handler.ts";
import { writeCache } from "../_shared/data_cache.ts";
import { gdeltBreakerKey, headlinesByTicker, tickerKey } from "../_shared/gdelt.ts";
import { classifyFiling, filingsToHeadlines, filingTitle, secHeadlines } from "../_shared/sec_news.ts";
import type { Filing } from "../_shared/sec.ts";
import { pickUnderlying, resolveUnderlyings, stripSuffix } from "../_shared/ticker_map.ts";
import {
  defaultTickerSearchCosts,
  ensureTickerSearch,
  moveKey,
  parseTickerSearch,
  parseTickerSearchCosts,
  runTickerSearch,
  searchFailKey,
  searchKey,
  tickerSearchLayer,
  type TickerSearchBody,
} from "../_shared/ticker_search.ts";
import { addPosition, createUser, db, deps, fakeFetch } from "./helpers.ts";

const today = () => new Date().toISOString().slice(0, 10);
const hoursAgo = (h: number) => new Date(Date.now() - h * 3600_000).toISOString();
const rand = () => crypto.randomUUID().replace(/[^a-z]/g, "").slice(0, 4).toUpperCase().padEnd(4, "Q");
const noNet = () => fakeFetch(() => new Response("no network", { status: 500 }));
const allow = new Map([["reuters.com", "Reuters"], ["cnbc.com", "CNBC"]]);

async function withBrief<T>(users: string[], fn: () => Promise<T>): Promise<T> {
  const { data } = await db.from("app_config").select("value").eq("key", "daily_brief").single();
  await db.from("app_config").update({ value: { ...(data!.value as object), percent: 0, users } }).eq("key", "daily_brief");
  try {
    return await fn();
  } finally {
    await db.from("app_config").update({ value: data!.value }).eq("key", "daily_brief");
  }
}

const spentMonth = async () => Number((await db.rpc("ticker_search_spent_month")).data ?? 0);

// ── capa 1: símbolo local → subyacente ──────────────────────────────────────

Deno.test("ticker_map: quitar el sufijo de bolsa solo si el base existe en EE. UU., en cualquier mercado", () => {
  assertEquals(stripSuffix("AAPL.BA"), "AAPL");
  assertEquals(stripSuffix("shel.l"), "SHEL");
  assertEquals(stripSuffix("SHOP.TO"), "SHOP");
  assertEquals(stripSuffix("BRK.B"), null, "una clase no es una bolsa");
  assertEquals(stripSuffix("AAPL"), null);
  assertEquals(pickUnderlying("AAPL.BA", null, true), { symbol: "AAPL.BA", underlying: "AAPL", kind: "heuristic" });
  assertEquals(pickUnderlying("TECO2.BA", null, false).underlying, "TECO2.BA", "sin base en EE. UU. no se adivina");
  assertEquals(pickUnderlying("NVDA", null, true).underlying, "NVDA");
  assertEquals(pickUnderlying("YPFD.BA", { ticker: "YPFD.BA", underlying: "YPF", kind: "alias" }, false).underlying, "YPF");
  // La tabla manda sobre la heurística.
  assertEquals(pickUnderlying("ALUA.BA", { ticker: "ALUA.BA", underlying: null, kind: "local" }, true).kind, "local");
});

Deno.test("resolveUnderlyings: tabla, heurística validada contra sec_ticker_cik y símbolos sin mapa", async () => {
  const base = rand();
  await db.from("sec_ticker_cik").upsert({ ticker: base, cik: "0009999001", title: `${base} CORP`, refreshed_at: new Date().toISOString() });
  const m = await resolveUnderlyings(deps(noNet().fetch), [`${base}.BA`, `${base}.MX`, "YPFD.BA", "ALUA.BA", "NOEXISTE.BA", "AAPL", "BTC-USD"]);
  assertEquals(m.get(`${base}.BA`)?.underlying, base);
  assertEquals(m.get(`${base}.MX`)?.underlying, base, "otro mercado, mismo mecanismo");
  assertEquals(m.get("YPFD.BA")?.underlying, "YPF");
  assertEquals(m.get("ALUA.BA")?.kind, "local");
  assertEquals(m.get("NOEXISTE.BA")?.underlying, "NOEXISTE.BA");
  assertEquals(m.get("AAPL")?.underlying, "AAPL");
  assertEquals(m.get("BTC-USD")?.underlying, "BTC-USD");
});

Deno.test("headlinesByTicker: AAPL.BA usa la caché y la búsqueda del subyacente y vuelve con el ticker del usuario", async () => {
  const base = rand();
  await db.from("sec_ticker_cik").upsert({ ticker: base, cik: "0009999002", title: `${base} CORP`, refreshed_at: new Date().toISOString() });
  const day = `2097-02-${String(1 + Math.floor(Math.random() * 27)).padStart(2, "0")}`;
  const item = { title: `${base} unveils chip`, url: "https://www.reuters.com/tech/chip-1", source: "Reuters", domain: "reuters.com", published_at: hoursAgo(2), language: "en" };
  await writeCache(deps(noNet().fetch), tickerKey(base, day), { name: base, items: [item], as_of: new Date().toISOString(), status: "ok" });
  const f = noNet();
  const r = await headlinesByTicker(deps(f.fetch), [`${base}.BA`, base], day);
  assertEquals(r.byTicker[`${base}.BA`].map((h) => h.title), [`${base} unveils chip`]);
  assertEquals(r.byTicker[base].length, 1);
  assertEquals(r.underlying[`${base}.BA`], base);
  assertEquals(f.calls.length, 0, "todo salió de la caché compartida");
});

// ── capa 3: SEC ─────────────────────────────────────────────────────────────

const filing = (form: string, items: string[], hours: number, extra: Partial<Filing> = {}): Filing => ({
  form, filed: hoursAgo(hours).slice(0, 10), report_date: null, items, accession: `0000-${form}-${hours}`,
  primary_document: "d.htm", url: `https://www.sec.gov/Archives/edgar/data/1/${hours}/d.htm`,
  index_url: "https://www.sec.gov/x-index.htm", accepted: hoursAgo(hours), ...extra,
});

Deno.test("sec_news: tipo de hecho legible, ventana de 72 h, resultados primero, sin enmiendas ni ítems sin interés", () => {
  assertEquals(classifyFiling({ form: "8-K", items: ["9.01", "2.02"] }), "results");
  assertEquals(classifyFiling({ form: "8-K", items: ["9.01"] }), null);
  assertEquals(classifyFiling({ form: "8-K/A", items: ["2.02"] }), null);
  assertEquals(classifyFiling({ form: "SC 13G", items: [] }), null);
  assertEquals(filingTitle("results", "8-K", "es"), "Presentó resultados trimestrales (8-K)");
  assertEquals(filingTitle("results", "8-K", "en"), "Reported quarterly results (8-K)");
  const now = Date.now();
  const list = filingsToHeadlines([
    filing("8-K", ["5.02"], 5),
    filing("8-K", ["2.02"], 30),
    filing("8-K", ["1.01"], 100), // fuera de las 72 h
    filing("10-Q", [], 60),
  ], now);
  assertEquals(list.map((h) => h.filing?.kind), ["results", "management"]);
  const h = list[0];
  assertEquals([h.source, h.domain, h.source_kind, h.image_url], ["SEC", "sec.gov", "filing", undefined]);
  assert(h.url.startsWith("https://www.sec.gov/"));
  // Sin `accepted` (caché vieja): la fecha a mediodía UTC, nunca en el futuro.
  const old = filingsToHeadlines([filing("8-K", ["2.02"], 1, { accepted: undefined, filed: new Date(now + 86400_000).toISOString().slice(0, 10) })], now);
  assert(Date.parse(old[0].published_at) <= now);
});

Deno.test("secHeadlines: EDGAR por CIK con el User-Agent del secreto; no emisores y símbolos locales no pegan a la SEC", async () => {
  const sym = rand();
  const cik = `00099${String(Math.floor(Math.random() * 90000) + 10000)}`;
  await db.from("sec_ticker_cik").upsert({ ticker: sym, cik, title: `${sym} CORP`, refreshed_at: new Date().toISOString() });
  const recent = new Date(Date.now() - 3600_000);
  const submissions = {
    name: `${sym} Corp`,
    filings: { recent: {
      form: ["8-K", "10-K"], filingDate: [recent.toISOString().slice(0, 10), "2020-02-01"],
      acceptanceDateTime: [recent.toISOString(), "2020-02-01T10:00:00.000Z"], accessionNumber: ["0001-26-000001", "0001-20-000001"],
      primaryDocument: ["a.htm", "b.htm"], items: ["2.02,9.01", ""], reportDate: ["", ""],
    } },
  };
  const f = fakeFetch((url) => url.includes(`CIK${cik}`) ? Response.json(submissions) : new Response("x", { status: 404 }));
  const d = deps(f.fetch, { SEC_USER_AGENT: "Porty test@example.com" });
  const r = await secHeadlines(d, sym);
  assertEquals(r.status, "ok");
  assertEquals(r.items.length, 1);
  assertEquals(r.items[0].filing, { form: "8-K", kind: "results" });
  const call = f.calls.find((c) => c.url.includes("data.sec.gov"))!;
  assertEquals((call.init?.headers as Record<string, string>)["User-Agent"], "Porty test@example.com");
  // Segunda vez: caché de 1 h, sin pedido nuevo.
  const n = f.calls.length;
  await secHeadlines(d, sym);
  assertEquals(f.calls.length, n);
  // Locales/cripto: ni siquiera se consulta; sin secreto: failed sin lanzar.
  assertEquals((await secHeadlines(d, "7203.T")).status, "skipped");
  assertEquals((await secHeadlines(d, "BTC-USD")).status, "skipped");
  assertEquals((await secHeadlines(deps(f.fetch, {}), rand())).status, "skipped");
});

Deno.test("headlinesByTicker: la presentación de la SEC entra al ticker, también un CEDEAR por su subyacente", async () => {
  await db.from("upstream_rate_gate").upsert({ source: "gdelt", next_allowed_at: new Date(Date.now() - 1000).toISOString() });
  const sym = rand();
  const cik = `00098${String(Math.floor(Math.random() * 90000) + 10000)}`;
  await db.from("sec_ticker_cik").upsert({ ticker: sym, cik, title: `${sym} CORP`, refreshed_at: new Date().toISOString() });
  const now = new Date();
  const submissions = { name: sym, filings: { recent: {
    form: ["8-K"], filingDate: [now.toISOString().slice(0, 10)], acceptanceDateTime: [new Date(Date.now() - 7200_000).toISOString()],
    accessionNumber: ["0002-26-000001"], primaryDocument: ["a.htm"], items: ["2.02"], reportDate: [""],
  } } };
  const day = `2096-03-${String(1 + Math.floor(Math.random() * 27)).padStart(2, "0")}`;
  const f = fakeFetch((url) =>
    url.includes("gdeltproject") ? Response.json({}) : url.includes(`CIK${cik}`) ? Response.json(submissions) : new Response("x", { status: 500 })
  );
  const d = deps(f.fetch, { SEC_USER_AGENT: "Porty test@example.com" });
  const r = await headlinesByTicker(d, [`${sym}.BA`], day);
  const items = r.byTicker[`${sym}.BA`];
  assertEquals(items.map((h) => h.source), ["SEC"]);
  assertEquals(r.status[`${sym}.BA`], "ok");
  assertFalse(f.calls.some((c) => c.url.includes("openai")), "la capa 4 nunca va por acá (ni en news-warm)");
  await db.from("data_source_cache").delete().eq("cache_key", gdeltBreakerKey);
});

Deno.test("news-warm no usa la búsqueda web por ticker y solo calienta usuarios activos", () => {
  const src = Deno.readTextFileSync(new URL("../news-warm/handler.ts", import.meta.url));
  assertFalse(/ticker_search|ensureTickerSearch|runTickerSearch/.test(src.replace(/\/\/.*$/gm, "")));
  assert(src.includes("daily_brief_warm_symbols_active"));
});

// ── capa 4: búsqueda web por ticker ─────────────────────────────────────────

function openAiReply(sym: string, name: string, url = "https://www.reuters.com/business/zz-launches-new-product-line-2026-11-23/") {
  const text = `- ${today()} | ${name} announced a new product line today.`;
  return Response.json({
    status: "completed",
    output: [
      { type: "web_search_call" },
      { type: "message", content: [{ type: "output_text", text, annotations: [{ type: "url_citation", url, title: `${name} launches new product line`, start_index: 0, end_index: text.length }] }] },
    ],
    usage: { input_tokens: 3000, output_tokens: 400 },
  });
}

const costs = { ...defaultTickerSearchCosts, monthlyUsd: 20 };
const envKey = { OPENAI_API_KEY: "sk-test" };

async function cleanTicker(sym: string) {
  await db.from("data_source_cache").delete().like("cache_key", `%:${sym}:%`);
  await db.from("upstream_rate_gate").delete().eq("source", `tsearch:${sym}`);
}

Deno.test("config: defaults, valores inválidos y 0 apaga", () => {
  assertEquals(parseTickerSearchCosts(undefined), defaultTickerSearchCosts);
  assertEquals(defaultTickerSearchCosts.monthlyUsd, 20);
  assertEquals(defaultTickerSearchCosts.minMovePct, 2.5);
  assertEquals(parseTickerSearchCosts({ ticker_search_monthly_usd: 0 }).monthlyUsd, 0);
  assertEquals(parseTickerSearchCosts({ ticker_search_monthly_usd: "x", ticker_search_min_move_pct: -1 }), defaultTickerSearchCosts);
  assertEquals(parseTickerSearchCosts({ ticker_search_monthly_usd: 5, ticker_search_min_move_pct: 4 }).minMovePct, 4);
});

Deno.test("parseTickerSearch: solo notas con fecha, citas de la allowlist, de esa empresa y sin consejo", () => {
  const mk = (lines: string[], anns: (i: number, len: number) => { url: string; title?: string }[] | null = () => null) => {
    let pos = 0;
    const annotations: { url: string; title?: string; start?: number; end?: number }[] = [];
    lines.forEach((l, i) => {
      const a = anns(i, l.length);
      if (a) for (const x of a) annotations.push({ ...x, start: pos, end: pos + l.length });
      pos += l.length + 1;
    });
    return { status: "completed", text: lines.join("\n"), annotations, searchCalls: 1, inputTokens: 0, outputTokens: 0 };
  };
  const d = today();
  const lines = [
    `- ${d} | Acme announced a new product line.`,
    `- ${d} | Acme shares: you should buy now.`,
    `- ${d} | Other Corp reported results.`,
    `- Acme did something without a date.`,
    `- ${d} | Acme said something with a blog source.`,
    `- 2020-01-01 | Acme old news.`,
  ];
  const urls = [
    "https://www.reuters.com/markets/acme-new-product-line-2026-11-23/",
    "https://www.cnbc.com/2026/11/23/acme-shares-surge.html",
    "https://www.cnbc.com/2026/11/23/other-corp-results.html",
    "https://www.cnbc.com/2026/11/23/acme-no-date-story.html",
    "https://someblog.example.com/acme-opinion-piece-2026",
    "https://www.reuters.com/markets/acme-old-news-2020-01-01/",
  ];
  const out = mk(lines, (i) => [{ url: urls[i], title: i === 2 ? "Other Corp reports results" : `Acme story ${i}` }]);
  const items = parseTickerSearch(out, allow, { name: "Acme", symbol: "ACME" }, Date.now());
  assertEquals(items.map((h) => h.domain), ["reuters.com"]);
  assertEquals(items[0].title, "Acme story 0");
  assert(items[0].url.startsWith("https://"));
});

Deno.test("capa 4 se dispara: sin noticias, se movió >= 2,5 %, sin caché ni tope; guarda cost_usd y comparte el resultado", async () => {
  const sym = rand();
  await cleanTicker(sym);
  const before = await spentMonth();
  const f = fakeFetch(() => openAiReply(sym, sym));
  const d = deps(f.fetch, envKey);
  const s = await ensureTickerSearch(d, { symbol: sym, name: sym, day: today(), pct: -3.1, allow, costs });
  assertEquals(s.state, "searching");
  await d.settle();
  assertEquals(f.calls.length, 1);
  const body = f.calls[0].body as { model: string; tools: { type: string; search_context_size: string; filters: { allowed_domains: string[] } }[] };
  assertEquals(body.tools[0].search_context_size, "low");
  assert(body.tools[0].filters.allowed_domains.includes("reuters.com"));
  const cached = await db.from("data_source_cache").select("body").eq("cache_key", searchKey(sym, today())).single();
  const b = cached.data!.body as TickerSearchBody;
  assertEquals(b.status, "ok");
  assert(b.cost_usd > 0.01, `cost_usd ${b.cost_usd}`);
  assertEquals(b.items[0].domain, "reuters.com");
  // Gasto: la reserva se ajustó al costo real.
  const spent = (await spentMonth()) - before;
  assert(Math.abs(spent - b.cost_usd) < 1e-6, `gasto ${spent} vs ${b.cost_usd}`);
  // Otro usuario el mismo día: sale de la caché, sin otra búsqueda.
  const again = await ensureTickerSearch(deps(f.fetch, envKey), { symbol: sym, name: sym, day: today(), pct: -3.1, allow, costs });
  assertEquals(again.state, "cached");
  assertEquals(f.calls.length, 1);
  await cleanTicker(sym);
});

Deno.test("capa 4 NO se dispara: sin movimiento, con caché, tope alcanzado, sin clave, apagada o con falla reciente", async () => {
  const sym = rand();
  await cleanTicker(sym);
  const f = fakeFetch(() => openAiReply(sym, sym));
  const d = deps(f.fetch, envKey);
  const ask = (over: Partial<Parameters<typeof ensureTickerSearch>[1]>, dd = d) =>
    ensureTickerSearch(dd, { symbol: sym, name: sym, day: today(), pct: 4, allow, costs, ...over });
  // (b) sin movimiento, justo debajo del umbral, o sin cotización.
  assertEquals(await ask({ pct: 1 }), { state: "skipped", reason: "no_move" });
  assertEquals(await ask({ pct: 2.49 }), { state: "skipped", reason: "no_move" });
  assertEquals(await ask({ pct: null }), { state: "skipped", reason: "no_move" });
  // Apagada / sin clave / sin nombre.
  assertEquals(await ask({ costs: { ...costs, monthlyUsd: 0 } }), { state: "skipped", reason: "disabled" });
  assertEquals(await ask({}, deps(f.fetch, {})), { state: "skipped", reason: "no_key" });
  assertEquals(await ask({ name: null }), { state: "skipped", reason: "no_name" });
  // (d) tope mensual: con 20 gastados de 20, no se busca ni se pasa por el arriendo.
  await db.from("news_ticker_search_spend").delete().neq("month", "1999-01-01");
  await db.rpc("ticker_search_budget_reserve", { p_cap_usd: 20, p_reserve_usd: 20 });
  assertEquals(await ask({}), { state: "skipped", reason: "budget" });
  assertEquals(await spentMonth(), 20, "el rechazo no suma gasto");
  // La falla por tope frena a los demás un rato (sin tocar de nuevo el arriendo).
  assertEquals(await ask({}), { state: "skipped", reason: "recent_failure" });
  await db.from("news_ticker_search_spend").delete().neq("month", "1999-01-01");
  await cleanTicker(sym);
  // (c) resultado de hoy cacheado (incluso "empty").
  await writeCache(d, searchKey(sym, today()), { status: "empty", items: [], as_of: new Date().toISOString(), model: "m", calls: 1, cost_usd: 0.02 });
  assertEquals(await ask({ pct: 9 }), { state: "cached", items: [] });
  await cleanTicker(sym);
  // Falla reciente de la búsqueda anterior.
  await writeCache(d, searchFailKey(sym, today()), { failed: true });
  assertEquals(await ask({}), { state: "skipped", reason: "recent_failure" });
  assertEquals(f.calls.length, 0, "ninguna de las condiciones llamó a OpenAI");
  await cleanTicker(sym);
});

Deno.test("capa 4: dos usuarios a la vez disparan UNA sola búsqueda (arriendo); el 2º ve `searching`", async () => {
  const sym = rand();
  await cleanTicker(sym);
  const f = fakeFetch(async () => {
    await new Promise((r) => setTimeout(r, 50));
    return openAiReply(sym, sym);
  });
  const d1 = deps(f.fetch, envKey), d2 = deps(f.fetch, envKey);
  const input = { symbol: sym, name: sym, day: today(), pct: 5, allow, costs };
  const before = await spentMonth();
  const [a, b] = await Promise.all([ensureTickerSearch(d1, input), ensureTickerSearch(d2, input)]);
  assertEquals([a.state, b.state], ["searching", "searching"]);
  await Promise.all([d1.settle(), d2.settle()]);
  assertEquals(f.calls.length, 1, "una sola búsqueda");
  assert((await spentMonth()) - before < costs.reserveUsd * 2, "una sola reserva");
  await cleanTicker(sym);
});

Deno.test("capa 4: una falla de OpenAI devuelve la reserva, se cachea y no se reintenta enseguida", async () => {
  const sym = rand();
  await cleanTicker(sym);
  const before = await spentMonth();
  const f = fakeFetch(() => new Response("boom", { status: 500 }));
  const d = deps(f.fetch, envKey);
  assertEquals((await ensureTickerSearch(d, { symbol: sym, name: sym, day: today(), pct: 5, allow, costs })).state, "searching");
  await d.settle();
  assertEquals(await spentMonth(), before, "HTTP 500: no se cobró");
  assertEquals(await ensureTickerSearch(d, { symbol: sym, name: sym, day: today(), pct: 5, allow, costs }), { state: "skipped", reason: "recent_failure" });
  assertEquals(f.calls.length, 1);
  await cleanTicker(sym);
});

Deno.test("contador mensual: las búsquedas acumulan costo real y el tope las corta", async () => {
  const sym = rand();
  await cleanTicker(sym);
  await db.from("news_ticker_search_spend").delete().neq("month", "1999-01-01");
  const tiny = { ...costs, monthlyUsd: 0.1, reserveUsd: 0.05 };
  const f = fakeFetch(() => openAiReply(sym, sym));
  const d = deps(f.fetch, envKey);
  // costo real ≈ 0.011 + tokens (~0.0016) ≈ 0.0127: caben varias, las reservas no pasan 0.1 a la vez.
  assertEquals((await ensureTickerSearch(d, { symbol: sym, name: sym, day: today(), pct: 5, allow, costs: tiny })).state, "searching");
  await d.settle();
  const spent = await spentMonth();
  assert(spent > 0.01 && spent < 0.02, `gasto ${spent}`);
  const row = await db.from("news_ticker_search_spend").select("searches").single();
  assertEquals(row.data!.searches, 1);
  await db.from("news_ticker_search_spend").delete().neq("month", "1999-01-01");
  await cleanTicker(sym);
});

Deno.test("tickerSearchLayer: solo sin noticias frescas, con tope por pedido, y CEDEAR comparte el subyacente", async () => {
  const [a, b, c] = [rand(), rand(), rand()];
  for (const s of [a, b, c]) await cleanTicker(s);
  for (const s of [a, b, c]) await writeCache(deps(noNet().fetch), moveKey(s, today()), { pct: 4 });
  const fresh = { title: "x", url: "https://www.reuters.com/a-b-c", source: "Reuters", domain: "reuters.com", published_at: hoursAgo(5), language: "en" as const };
  const f = fakeFetch((_u, _i, n) => openAiReply("x", "Name"));
  const d = deps(f.fetch, envKey);
  const r = await tickerSearchLayer(d, {
    symbols: [{ user: a, underlying: a }, { user: `${a}.BA`, underlying: a }, { user: b, underlying: b }, { user: c, underlying: c }],
    byTicker: { [a]: [], [`${a}.BA`]: [], [b]: [fresh], [c]: [] },
    status: { [a]: "ok", [`${a}.BA`]: "ok", [b]: "ok", [c]: "failed" },
    names: { [a]: "Name", [b]: "Name", [c]: "Name" },
    day: today(), allow, costs: { ...costs, maxPerRequest: 3 },
  });
  await d.settle();
  assertEquals(r.searching.sort(), [a, `${a}.BA`].sort(), "el CEDEAR y su subyacente comparten la búsqueda");
  assertEquals(r.outcomes[b], undefined, "con noticias frescas no se evalúa");
  assertEquals(r.outcomes[c], undefined, "fuentes caídas (failed): no se sabe si hay noticias, no se gasta");
  assertEquals(f.calls.length, 1);
  // Tope por pedido: 0 = no dispara.
  const sym2 = rand();
  await cleanTicker(sym2);
  await writeCache(d, moveKey(sym2, today()), { pct: 4 });
  const capped = await tickerSearchLayer(d, {
    symbols: [{ user: sym2, underlying: sym2 }], byTicker: { [sym2]: [] }, status: { [sym2]: "ok" }, names: { [sym2]: "Name" },
    day: today(), allow, costs: { ...costs, maxPerRequest: 0 },
  });
  assertEquals(capped.searching, []);
  assertEquals(capped.outcomes[sym2], "per_request_cap");
  for (const s of [a, b, c, sym2]) await cleanTicker(s);
});

Deno.test("daily-brief: Premium recibe `searching`, la app vuelve a pedir y ve las notas; Free y cortesía nunca disparan la capa 4", async () => {
  const sym = rand();
  await cleanTicker(sym);
  await db.from("sec_ticker_cik").upsert({ ticker: sym, cik: "0009999003", title: `${sym} CORP`, refreshed_at: new Date().toISOString() });
  await db.from("upstream_rate_gate").upsert({ source: "gdelt", next_allowed_at: new Date(Date.now() - 1000).toISOString() });
  await writeCache(deps(noNet().fetch), moveKey(sym, today()), { pct: 6.2 });
  const premium = await createUser("premium");
  const free = await createUser("free");
  await addPosition(premium.id, sym);
  await addPosition(free.id, sym);
  const f = fakeFetch((url, init) =>
    url.includes("gdeltproject")
      ? Response.json({})
      : url.includes("openai") && String(init?.body).includes(`ticker ${sym}`)
      ? openAiReply(sym, sym)
      : new Response("x", { status: 500 })
  );
  // Búsquedas por ticker (los digests de temas también van a OpenAI).
  const tickerCalls = () =>
    f.calls.filter((c) => c.url.includes("openai") && String((c.body as { input?: string })?.input).includes(`ticker ${sym}`)).length;
  const get = (jwt: string) =>
    new Request(`http://local/functions/v1/daily-brief?scope=feed&lang=es&day=${today()}`, { headers: { Authorization: `Bearer ${jwt}` } });
  await withBrief([premium.id, free.id], async () => {
    const dFree = deps(f.fetch, envKey);
    const rf = await (await handle(get(free.jwt), dFree)).json();
    await dFree.settle();
    assertEquals(rf.mine, []);
    assertEquals(rf.searching, undefined);
    assertEquals(tickerCalls(), 0, "Free no dispara búsquedas");

    const d1 = deps(f.fetch, envKey);
    const first = await (await handle(get(premium.jwt), d1)).json();
    assertEquals(first.mine_status, "searching");
    assertEquals(first.searching.tickers, [sym]);
    assertEquals(first.searching.retry_after_s, 10);
    assertEquals(first.mine, []);
    await d1.settle();
    assertEquals(tickerCalls(), 1);

    const d2 = deps(f.fetch, envKey);
    const second = await (await handle(get(premium.jwt), d2)).json();
    await d2.settle();
    assertEquals(second.mine_status, "ok");
    assertEquals(second.searching, undefined);
    assertEquals(second.mine.map((m: { ticker: string; domain: string }) => [m.ticker, m.domain]), [[sym, "reuters.com"]]);
    assertEquals(tickerCalls(), 1, "la segunda vez sale de la caché");
  });
  await cleanTicker(sym);
  // Los digests de temas fallaron (500): sacar sus marcas para no afectar a otros tests.
  await db.from("data_source_cache").delete().or("cache_key.like.digest:%,cache_key.like.digestfail:%");
  await db.from("data_source_cache").delete().eq("cache_key", gdeltBreakerKey);
});

Deno.test("runTickerSearch: sin clave no hace nada (y devuelve la reserva)", async () => {
  const sym = rand();
  await cleanTicker(sym);
  await db.from("news_ticker_search_spend").delete().neq("month", "1999-01-01");
  await db.rpc("ticker_search_budget_reserve", { p_cap_usd: 20, p_reserve_usd: 0.05 });
  const f = noNet();
  const r = await runTickerSearch(deps(f.fetch, {}), { symbol: sym, name: sym, day: today(), allow, reservedUsd: 0.05 });
  assertEquals(r, null);
  assertEquals(f.calls.length, 0);
  await db.from("news_ticker_search_spend").delete().neq("month", "1999-01-01");
  await cleanTicker(sym);
});

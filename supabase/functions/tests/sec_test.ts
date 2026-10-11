// SEC EDGAR: parsers puros con respuestas REALES guardadas (fixtures/sec,
// recortadas a los conceptos que se usan) y la función `sec` contra la
// base local, sin red: el `fetch` falso sirve los fixtures.

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { handle } from "../sec/handler.ts";
import {
  estimateNextReport,
  extractFundamentals,
  htmlToText,
  parseEftsHits,
  parseFilingIndex,
  parseTickerMap,
  pressReleaseDocument,
} from "../_shared/sec.ts";
import { pressName } from "../_shared/gdelt.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { createUser, db, deps, fakeFetch } from "./helpers.ts";

const dir = new URL("./fixtures/sec/", import.meta.url);
const text = (name: string) => Deno.readTextFile(new URL(name, dir));
const fixture = async (name: string) => JSON.parse(await text(name));

// ---------------------------------------------------------------------------
// Puras
// ---------------------------------------------------------------------------

Deno.test("ticker map: CIK con 10 dígitos y clases con punto (BRK-B → BRK.B)", async () => {
  const rows = parseTickerMap(await fixture("company_tickers.json"));
  const by = new Map(rows.map((r) => [r.ticker, r]));
  assertEquals(by.get("AAPL")?.cik, "0000320193");
  assertEquals(by.get("BRK.B")?.cik, by.get("BRK-B")?.cik);
});

Deno.test("fundamentals AAPL: TTM de 4 trimestres, Q4 calculado y márgenes", async () => {
  const f = extractFundamentals(await fixture("facts_AAPL.json"));
  assertEquals(f.currency, "USD");
  assertEquals(f.ttm_basis, "4q");
  assertEquals(f.ttm_end, "2026-06-27");
  assertEquals(f.revenue_ttm, 466_823_000_000);
  assertEquals(f.eps_diluted_ttm, 8.71);
  assertEquals(f.net_margin_pct, 27.6);
  assertEquals(f.quarters.map((q) => q.label), ["T4 FY25", "T1 FY26", "T2 FY26", "T3 FY26"]);
  assertEquals(f.quarters[0].derived, true);
  assertEquals(f.quarters[3].eps_diluted, 2.02);
  assertEquals(f.years.map((y) => y.fiscal_year), [2023, 2024, 2025]);
  assert(f.shares_outstanding! > 14e9);
});

Deno.test("fundamentals KO: el EPS sale en USD/shares, no en la unidad 'pure'", async () => {
  const f = extractFundamentals(await fixture("facts_KO.json"));
  assertEquals(f.eps_diluted_ttm, 3.18);
  assertEquals(f.quarters.at(-1)?.eps_diluted, 0.91);
});

Deno.test("fundamentals MELI (local, opera en LatAm): 10-Q en USD", async () => {
  const f = extractFundamentals(await fixture("facts_MELI.json"));
  assertEquals(f.currency, "USD");
  assertEquals(f.quarters.at(-1)?.label, "T2 FY26");
  assertEquals(f.quarters.at(-1)?.revenue, 10_169_000_000);
  assert(f.quarters.at(-1)!.revenue_yoy_pct! > 0);
});

Deno.test("fundamentals BABA (20-F): solo años, en su moneda (CNY)", async () => {
  const f = extractFundamentals(await fixture("facts_BABA.json"));
  assertEquals(f.currency, "CNY");
  assertEquals(f.ttm_basis, "annual");
  assertEquals(f.quarters, []);
  assertEquals(f.years.at(-1)?.fiscal_year, 2026);
});

Deno.test("fundamentals YPF (ifrs-full): toma el concepto con el dato más nuevo", async () => {
  const f = extractFundamentals(await fixture("facts_YPF.json"));
  assertEquals(f.ttm_end, "2025-12-31");
  assertEquals(f.revenue_ttm, 18_448_000_000);
  assertEquals(f.eps_diluted_ttm, -2.11);
});

Deno.test("próximo reporte: mismo trimestre un año después; viejo → null", () => {
  const aapl = ["2026-07-30", "2026-04-30", "2026-01-29", "2025-10-30", "2025-07-31"];
  assertEquals(estimateNextReport(aapl, "2026-10-11"), { date: "2026-10-29", basis: "same_quarter_last_year" });
  assertEquals(estimateNextReport(["2026-08-05"], "2026-10-11"), {
    date: "2026-11-04",
    basis: "last_report_plus_quarter",
  });
  assertEquals(estimateNextReport(["2024-05-01"], "2026-10-11"), null);
  assertEquals(estimateNextReport([], "2026-10-11"), null);
});

Deno.test("índice de un 8-K: el comunicado es el EX-99.1", async () => {
  const doc = pressReleaseDocument(parseFilingIndex(await text("index_meli.htm")));
  assertEquals(doc?.type, "EX-99.1");
  assertStringIncludes(doc!.url, "/Archives/edgar/data/1099590/000109959026000021/");
});

Deno.test("comunicado: HTML → texto legible", async () => {
  const t = htmlToText(await text("ex991_aapl.htm"));
  assertStringIncludes(t, "Apple reports third quarter results");
  assert(!/<\/?[a-z][^>]*>/i.test(t));
});

Deno.test("búsqueda full-text: exhibits de resultados de 6-K, el más nuevo primero", async () => {
  const hits = parseEftsHits(await fixture("efts_baba.json"));
  assertEquals(hits[0], {
    accession: "0001104659-26-099220",
    file: "tm2623667d1_ex99-1.htm",
    filed: "2026-08-20",
    type: "EX-99.1",
  });
  assert(hits.every((h) => h.type.startsWith("EX-99")));
});

Deno.test("nombre para la prensa: sin sufijos societarios", () => {
  assertEquals(pressName("NVIDIA CORP"), "Nvidia");
  assertEquals(pressName("YPF SOCIEDAD ANONIMA"), "YPF Sociedad Anonima");
  assertEquals(pressName("Apple Inc."), "Apple");
  assertEquals(pressName("MERCADOLIBRE INC"), "Mercadolibre");
  assertEquals(pressName("Alibaba Group Holding Ltd"), "Alibaba");
});

// ---------------------------------------------------------------------------
// Función `sec` (base local + fetch falso)
// ---------------------------------------------------------------------------

const now = Date.parse("2026-10-11T12:00:00Z");
const env = { SEC_USER_AGENT: "Porty test test@porty.local" };

const routes: [RegExp, string][] = [
  [/company_tickers\.json$/, "company_tickers.json"],
  [/submissions\/CIK0000320193\.json$/, "submissions_AAPL.json"],
  [/submissions\/CIK0001099590\.json$/, "submissions_MELI.json"],
  [/submissions\/CIK0001577552\.json$/, "submissions_BABA.json"],
  [/companyfacts\/CIK0000320193\.json$/, "facts_AAPL.json"],
  [/companyfacts\/CIK0001099590\.json$/, "facts_MELI.json"],
  [/companyfacts\/CIK0001577552\.json$/, "facts_BABA.json"],
  [/0000320193-26-000018-index\.htm$/, "index_aapl.htm"],
  [/a8-kex991q3202606272026\.htm$/, "ex991_aapl.htm"],
  [/efts\.sec\.gov/, "efts_baba.json"],
  [/tm2623667d1_ex99-1\.htm$/, "ex991_baba.htm"],
];

function secFetch(failing = false) {
  return fakeFetch(async (url) => {
    if (failing) return new Response("busy", { status: 503 });
    for (const [re, name] of routes) if (re.test(url)) return new Response(await text(name));
    return new Response("not found", { status: 404 });
  });
}

const req = (jwt: string | null, endpoint: string, ticker: string) =>
  new Request(`http://local/functions/v1/sec/${endpoint}?ticker=${ticker}`, {
    headers: jwt ? { Authorization: `Bearer ${jwt}` } : {},
  });

const asUser = (jwt: string) =>
  createClient(
    Deno.env.get("API_URL") ?? "http://127.0.0.1:54321",
    Deno.env.get("ANON_KEY") ?? "",
    { global: { headers: { Authorization: `Bearer ${jwt}` } }, auth: { persistSession: false } },
  );

async function resetSecCache() {
  await db.from("data_source_cache").delete().like("cache_key", "sec:%");
  await db.from("sec_ticker_cik").delete().neq("ticker", "");
}

Deno.test("sec: sin JWT 401; Free/Premium 403 sin tocar la SEC", async () => {
  const f = secFetch();
  assertEquals((await handle(req(null, "earnings", "AAPL"), deps(f.fetch, env, () => now))).status, 401);
  for (const tier of ["free", "premium"] as const) {
    const u = await createUser(tier);
    const r = await handle(req(u.jwt, "earnings", "AAPL"), deps(f.fetch, env, () => now));
    assertEquals(r.status, 403);
    assertEquals((await r.json()).error.type, "plan_required");
  }
  assertEquals(f.calls.length, 0);
});

Deno.test("sec earnings AAPL (Gold): comunicado, trimestres y fecha ESTIMADA; después sale de la caché", async () => {
  await resetSecCache();
  const gold = await createUser("gold");
  const f = secFetch();
  const d = deps(f.fetch, env, () => now);

  const r = await handle(req(gold.jwt, "earnings", "AAPL"), d);
  await d.settle();
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.status, "ok");
  assertEquals(body.filer, "domestic");
  assertStringIncludes(body.latest_release.text, "third quarter");
  assertEquals(body.latest_release.filed, "2026-07-30");
  assertEquals(body.next_report, { date: "2026-10-29", estimated: true, basis: "same_quarter_last_year" });
  assertEquals(body.quarters.length, 4);
  assertEquals(body.source.name, "SEC EDGAR");
  for (const call of f.calls) {
    assertEquals((call.init?.headers as Record<string, string>)["User-Agent"], env.SEC_USER_AGENT);
  }

  const before = f.calls.length;
  const again = await handle(req(gold.jwt, "earnings", "AAPL"), d);
  assertEquals(again.headers.get("x-cache"), "hit");
  await again.body?.cancel();
  assertEquals(f.calls.length, before);
});

Deno.test("sec earnings BABA (extranjero): comunicado del 6-K por búsqueda de texto", async () => {
  const gold = await createUser("gold");
  const r = await handle(req(gold.jwt, "earnings", "BABA"), deps(secFetch().fetch, env, () => now));
  const body = await r.json();
  assertEquals(body.filer, "foreign");
  assertEquals(body.latest_release.form, "6-K");
  assertStringIncludes(body.latest_release.text, "June Quarter 2026 Results");
  assertEquals(body.currency, "CNY");
  // 2025-08 no está en la búsqueda recortada: la estimación sale de +91 días.
  assert(body.next_report.estimated);
});

Deno.test("sec fundamentals MELI y filings: datos coherentes", async () => {
  const gold = await createUser("gold");
  const d = deps(secFetch().fetch, env, () => now);
  const f = await (await handle(req(gold.jwt, "fundamentals", "MELI"), d)).json();
  assertEquals(f.status, "ok");
  assertEquals(f.company_name, "MERCADOLIBRE INC");
  assertEquals(f.ttm_basis, "4q");
  const filings = await (await handle(req(gold.jwt, "filings", "MELI"), d)).json();
  assertEquals(filings.filings[0].form, "8-K");
  assert(filings.filings.some((x: { items: { code: string }[] }) => x.items.some((i) => i.code === "2.02")));
});

Deno.test("sec: ticker sin CIK → respuesta controlada, no error", async () => {
  const gold = await createUser("gold");
  const r = await handle(req(gold.jwt, "earnings", "ZZZZ"), deps(secFetch().fetch, env, () => now));
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.status, "not_found");
  assertStringIncludes(body.message, "No hay presentaciones ante la SEC para ZZZZ");
});

Deno.test("sec: la cortesía semanal de un ticker habilita ESE ticker a un Premium", async () => {
  const premium = await createUser("premium");
  // Como en la app: la cortesía la gasta el usuario con la RPC.
  const monday = new Date();
  monday.setUTCDate(monday.getUTCDate() - ((monday.getUTCDay() + 6) % 7));
  const consumed = await asUser(premium.jwt).rpc("consume_weekly_free_analysis", {
    p_week_start: monday.toISOString().slice(0, 10),
    p_ticker: "AAPL",
  });
  assertEquals(consumed.data?.ok, true);
  const d = deps(secFetch().fetch, env, () => now);
  const ok = await handle(req(premium.jwt, "fundamentals", "AAPL"), d);
  assertEquals(ok.status, 200);
  await ok.body?.cancel();
  const locked = await handle(req(premium.jwt, "fundamentals", "MELI"), d);
  assertEquals(locked.status, 403);
  await locked.body?.cancel();
});

Deno.test("sec: si la SEC falla, sirve el último dato aunque esté vencido", async () => {
  const gold = await createUser("gold");
  await handle(req(gold.jwt, "fundamentals", "AAPL"), deps(secFetch().fetch, env, () => now)).then((r) => r.body?.cancel());
  const later = now + 3 * 86_400_000;
  const r = await handle(req(gold.jwt, "fundamentals", "AAPL"), deps(secFetch(true).fetch, env, () => later));
  assertEquals(r.status, 200);
  assertEquals(r.headers.get("x-cache"), "stale");
  assertEquals((await r.json()).revenue_ttm, 466_823_000_000);
});

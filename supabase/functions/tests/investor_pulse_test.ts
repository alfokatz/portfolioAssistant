import { assert, assertEquals } from "jsr:@std/assert@1";
import { config, handle, isFresh } from "../investor-pulse/handler.ts";
import {
  googleNewsUrl,
  type Investor,
  parseForm4,
  parseGoogleRss,
  parseSchedule13,
  recentFilings,
  sameEvent,
  selectNews,
  tickerMap,
  weekOf,
} from "../investor-pulse/sources.ts";
import { createUser, db, deps, fakeFetch } from "./helpers.ts";

config.secDelayMs = 0;

const week = weekOf("2026-09-21")!;

const buffett: Investor = {
  id: "warren-buffett",
  display_name: "Warren Buffett",
  organization: "Berkshire Hathaway",
  kind: "investor",
  search_terms: ["Warren Buffett", "Greg Abel", "Berkshire Hathaway"],
  ciks: ["1067983"],
  sort: 10,
};

function rssItem(title: string, source: string, date: string, url = `https://news.google.com/${crypto.randomUUID()}`) {
  return `<item><title>${title} - ${source}</title><link>${url}</link>` +
    `<pubDate>${new Date(date).toUTCString()}</pubDate>` +
    `<source url="https://x.com">${source}</source></item>`;
}

const rss = (...items: string[]) => `<rss><channel>${items.join("")}</channel></rss>`;

/// Form 4 recortado de uno real (Berkshire comprando Lennar, 2026-09-30).
function form4(ownerCik: string, rows: [string, number][], symbol = "LEN") {
  const tx = rows.map(([code, shares]) =>
    `<nonDerivativeTransaction><transactionCoding><transactionCode>${code}</transactionCode></transactionCoding>` +
    `<transactionAmounts><transactionShares><value>${shares}</value></transactionShares></transactionAmounts>` +
    `</nonDerivativeTransaction>`
  ).join("");
  return `<ownershipDocument><issuer><issuerCik>0000920760</issuerCik><issuerName>LENNAR CORP /NEW/</issuerName>` +
    `<issuerTradingSymbol>${symbol}</issuerTradingSymbol></issuer>` +
    `<reportingOwner><reportingOwnerId><rptOwnerCik>${ownerCik}</rptOwnerCik></reportingOwnerId></reportingOwner>` +
    `<nonDerivativeTable>${tx}</nonDerivativeTable></ownershipDocument>`;
}

function submissions(rows: { form: string; date: string; acc: string; doc: string; report?: string }[]) {
  return {
    name: "BERKSHIRE HATHAWAY INC",
    filings: {
      recent: {
        form: rows.map((r) => r.form),
        filingDate: rows.map((r) => r.date),
        accessionNumber: rows.map((r) => r.acc),
        primaryDocument: rows.map((r) => r.doc),
        reportDate: rows.map((r) => r.report ?? ""),
      },
    },
  };
}

// ---------------------------------------------------------------------------
// Funciones puras
// ---------------------------------------------------------------------------

Deno.test("weekOf: solo lunes válidos", () => {
  assertEquals(weekOf("2026-09-21"), { monday: "2026-09-21", friday: "2026-09-25", saturday: "2026-09-26" });
  assertEquals(weekOf("2026-09-22"), null); // martes
  assertEquals(weekOf("2026-02-30"), null);
  assertEquals(weekOf("21/09/2026"), null);
});

Deno.test("la búsqueda une los términos con OR y usa el rango de la semana", () => {
  const q = new URL(googleNewsUrl(buffett, week)).searchParams.get("q");
  assertEquals(
    q,
    '("Warren Buffett" OR "Greg Abel" OR "Berkshire Hathaway") after:2026-09-21 before:2026-09-26',
  );
});

Deno.test("parseGoogleRss saca el ' - Medio' del título y descarta items rotos", () => {
  const items = parseGoogleRss(rss(
    rssItem("Warren Buffett buys more Lennar stock", "Reuters", "2026-09-24T15:00:00Z"),
    `<item><title>sin link</title><pubDate>Wed, 23 Sep 2026 10:00:00 GMT</pubDate></item>`,
  ));
  assertEquals(items.length, 1);
  assertEquals(items[0].headline, "Warren Buffett buys more Lennar stock");
  assertEquals(items[0].source, "Reuters");
});

Deno.test("selectNews: nombra al inversor, es de mercado, cae en la semana, sin repetidos", () => {
  const raw = parseGoogleRss(rss(
    rssItem("Warren Buffett buys more Lennar stock", "Reuters", "2026-09-24T15:00:00Z"),
    // mismo hecho, otro medio
    rssItem("Warren Buffett buys more Lennar shares stock", "CNBC", "2026-09-24T16:00:00Z"),
    // no es de mercado
    rssItem("Warren Buffett celebrates birthday with family", "People", "2026-09-23T10:00:00Z"),
    // menciona otro Buffett
    rssItem("Jimmy Buffett tribute concert sells out", "Billboard", "2026-09-23T10:00:00Z"),
    // fuera de la semana
    rssItem("Warren Buffett trims Apple stake", "WSJ", "2026-09-18T10:00:00Z"),
    // viernes a la noche en Nueva York = sábado temprano en UTC: entra
    rssItem("Greg Abel says Berkshire stock buybacks paused", "Bloomberg", "2026-09-26T01:00:00Z"),
  ));
  const picked = selectNews(raw, buffett, week).map((h) => h.source);
  assertEquals(picked, ["Reuters", "Bloomberg"]);
});

Deno.test("sameEvent reconoce el mismo hecho contado distinto", () => {
  assert(sameEvent("Buffett buys more Lennar stock", "Buffett buys more Lennar shares"));
  assert(!sameEvent("Buffett buys more Lennar stock", "Ackman warns about the Fed"));
});

Deno.test("recentFilings: solo la semana y los formularios que importan, sin el prefijo xsl", () => {
  const f = recentFilings(submissions([
    { form: "4", date: "2026-09-25", acc: "0001193125-26-403089", doc: "xslF345X06/ownership.xml" },
    { form: "SD", date: "2026-09-25", acc: "a", doc: "x.htm" },
    { form: "4", date: "2026-09-18", acc: "b", doc: "xslF345X06/ownership.xml" },
    { form: "13F-HR", date: "2026-09-22", acc: "c", doc: "xslForm13F_X02/primary_doc.xml", report: "2026-06-30" },
    { form: "SCHEDULE 13G/A", date: "2026-09-23", acc: "d", doc: "xslSCHEDULE_13G_X02/primary_doc.xml" },
  ]), "0001067983", week);
  assertEquals(f.map((x) => x.form), ["4", "13F-HR", "SCHEDULE 13G/A"]);
  assertEquals(f[0].rawDocument, "ownership.xml");
  assertEquals(f[0].cik, "1067983");
  assertEquals(f[1].reportDate, "2026-06-30");
});

Deno.test("parseForm4: el inversor tiene que ser quien opera; suma compras y ventas", () => {
  const p = parseForm4(form4("0001067983", [["P", 5200], ["P", 12289], ["S", 100]], "LEN, LEN.B"), "1067983");
  assertEquals(p, { issuerName: "LENNAR CORP /NEW/", issuerTicker: "LEN", bought: 17489, sold: 100 });
  // Form 4 de un directivo de Berkshire: aparece en el CIK de Berkshire,
  // pero no lo presentó Berkshire.
  assertEquals(parseForm4(form4("0000315090", [["P", 10]]), "1067983"), null);
  // Solo premios o regalos (A, G): no es una operación de mercado.
  assertEquals(parseForm4(form4("0001067983", [["G", 10], ["A", 5]]), "1067983"), null);
});

Deno.test("parseSchedule13 y tickerMap llevan de la emisora al ticker", () => {
  const xml = `<edgarSubmission><ns1:issuerInfo><ns1:issuerCik>0000920760</ns1:issuerCik>` +
    `<ns1:issuerName>LENNAR CORPORATION</ns1:issuerName></ns1:issuerInfo></edgarSubmission>`;
  assertEquals(parseSchedule13(xml), { issuerName: "LENNAR CORPORATION", issuerCik: "920760" });
  const map = tickerMap({
    "0": { cik_str: 920760, ticker: "LEN", title: "LENNAR CORP /NEW/" },
    "1": { cik_str: 920760, ticker: "LEN-B", title: "LENNAR CORP /NEW/" },
    "2": { cik_str: 1067983, ticker: "BRK-B", title: "BERKSHIRE HATHAWAY INC" },
  });
  assertEquals(map.get("920760"), "LEN");
  assertEquals(map.get("1067983"), "BRK.B");
});

Deno.test("isFresh: 6 h mientras la semana se asienta, 7 días después", () => {
  const sat = Date.parse("2026-09-26T00:00:00Z");
  const hours = (h: number) => h * 3_600_000;
  // armado el sábado: a las 7 h ya no sirve
  assert(isFresh(new Date(sat).toISOString(), week, sat + hours(5)));
  assert(!isFresh(new Date(sat).toISOString(), week, sat + hours(7)));
  // armado el jueves siguiente: sirve varios días
  const thu = sat + hours(5 * 24);
  assert(isFresh(new Date(thu).toISOString(), week, thu + hours(72)));
});

// ---------------------------------------------------------------------------
// Handler (Postgres local, fetch falso)
// ---------------------------------------------------------------------------

const now = () => Date.parse("2026-09-28T12:00:00Z");
const env = { SEC_USER_AGENT: "Porty tests test@example.com" };

function req(jwt: string | null, w = "2026-09-21"): Request {
  return new Request(`http://local/functions/v1/investor-pulse?week=${w}`, {
    headers: jwt ? { Authorization: `Bearer ${jwt}` } : {},
  });
}

/// Google devuelve una nota de Buffett para su búsqueda y nada para el
/// resto; la SEC, un Form 4 de compra de Lennar en el CIK de Berkshire.
function upstream(state: { down?: boolean } = {}) {
  return fakeFetch((url) => {
    if (state.down) return new Response("down", { status: 503 });
    if (url.startsWith("https://news.google.com/")) {
      const q = new URL(url).searchParams.get("q") ?? "";
      return new Response(
        q.includes("Warren Buffett")
          ? rss(rssItem("Warren Buffett buys more Lennar stock", "Reuters", "2026-09-24T15:00:00Z"))
          : rss(),
      );
    }
    if (url.includes("CIK0001067983")) {
      return Response.json(submissions([
        { form: "4", date: "2026-09-25", acc: "0001193125-26-403089", doc: "xslF345X06/ownership.xml" },
      ]));
    }
    if (url.includes("/submissions/")) return Response.json(submissions([]));
    if (url.endsWith("ownership.xml")) return new Response(form4("0001067983", [["P", 638813]]));
    return new Response("not found", { status: 404 });
  });
}

async function clearWeek(w = "2026-09-21") {
  await db.from("investor_pulse_cache").delete().eq("week_start", w);
}

Deno.test("sin JWT → 401", async () => {
  const r = await handle(req(null), deps(upstream().fetch, env, now));
  assertEquals(r.status, 401);
});

Deno.test("semana inválida o futura → 400", async () => {
  const user = await createUser("gold");
  for (const w of ["2026-09-22", "2026-10-05", "2026-01-05"]) {
    const r = await handle(req(user.jwt, w), deps(upstream().fetch, env, now));
    assertEquals(r.status, 400, w);
    await r.body?.cancel();
  }
});

Deno.test("arma filings + noticias con ids estables y la caché sirve a otro usuario", async () => {
  await clearWeek();
  const a = await createUser("gold");
  const b = await createUser("free");
  const f = upstream();
  const first = await handle(req(a.jwt), deps(f.fetch, env, now));
  assertEquals(first.headers.get("x-cache"), "miss");
  const body = await first.json();
  assertEquals(body.week_start, "2026-09-21");
  const [filing, news] = body.items;
  assertEquals(filing.id, "i1");
  assertEquals(filing.type, "filing");
  assertEquals(filing.action, "buy");
  assertEquals(filing.issuer_ticker, "LEN");
  assertEquals(filing.shares, 638813);
  assertEquals(filing.url, "https://www.sec.gov/Archives/edgar/data/1067983/000119312526403089/0001193125-26-403089-index.htm");
  assertEquals(news.id, "i2");
  assertEquals(news.headline, "Warren Buffett buys more Lennar stock");
  // A la SEC se le manda el contacto configurado.
  const secCall = f.calls.find((c) => c.url.includes("data.sec.gov"))!;
  assertEquals(new Headers(secCall.init?.headers).get("User-Agent"), env.SEC_USER_AGENT);

  const calls = f.calls.length;
  const second = await handle(req(b.jwt), deps(f.fetch, env, now));
  assertEquals(second.headers.get("x-cache"), "hit");
  assertEquals((await second.json()).items.length, body.items.length);
  assertEquals(f.calls.length, calls);
});

Deno.test("si las fuentes se caen, sirve la caché vieja; sin caché → 502", async () => {
  await clearWeek();
  const user = await createUser("gold");
  let t = now();
  const state = { down: false };
  const f = upstream(state);
  await (await handle(req(user.jwt), deps(f.fetch, env, () => t))).body?.cancel();
  t += 7 * 3_600_000; // vencida (semana sin asentar: 6 h)
  state.down = true;
  const stale = await handle(req(user.jwt), deps(f.fetch, env, () => t));
  assertEquals(stale.headers.get("x-cache"), "stale");
  assert((await stale.json()).items.length > 0);

  await clearWeek();
  const none = await handle(req(user.jwt), deps(f.fetch, env, () => t));
  assertEquals(none.status, 502);
  await none.body?.cancel();
});

Deno.test("sin SEC_USER_AGENT no se llama a la SEC: solo noticias", async () => {
  await clearWeek();
  const user = await createUser("gold");
  const f = upstream();
  const r = await handle(req(user.jwt), deps(f.fetch, {}, now));
  const body = await r.json();
  assert(body.items.every((i: { type: string }) => i.type === "news"));
  assert(!f.calls.some((c) => c.url.includes("sec.gov")));
  await clearWeek();
});

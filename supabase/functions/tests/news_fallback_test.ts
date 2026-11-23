// Confiabilidad de las noticias del brief/feed: respaldo Finnhub/Yahoo cuando
// GDELT falla (429), viene vacío o no cubre el ticker; sirve lo cacheado si
// todo falla; `mine_status` distingue "sin noticias" de "no se pudo consultar";
// `image_url` solo https. Base local real (`supabase start`); GDELT, Finnhub y
// Yahoo son un `fetch` falso (ninguna llamada real). Correr:
//   cd supabase/functions && deno test --allow-net --allow-env --allow-read tests/news_fallback_test.ts

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { handle } from "../daily-brief/handler.ts";
import { writeCache } from "../_shared/data_cache.ts";
import { gdeltBreakerKey, headlinesByTicker, parseArticles, tickerKey } from "../_shared/gdelt.ts";
import {
  allowedDomainFor, dedupeHeadlines, isUsPlainSymbol, parseFinnhubNews, parseYahooNews, safeImageUrl,
} from "../_shared/news_fallback.ts";
import { addPosition, createUser, db, deps, fakeFetch } from "./helpers.ts";

const allow = new Map([
  ["reuters.com", "Reuters"], ["cnbc.com", "CNBC"], ["finance.yahoo.com", "Yahoo Finance"], ["infobae.com", "Infobae"],
]);
const unix = (hoursAgo: number) => Math.floor((Date.now() - hoursAgo * 3600_000) / 1000);
const seen = (hoursAgo: number) => new Date(Date.now() - hoursAgo * 3600_000).toISOString().replace(/[-:]/g, "").slice(0, 15) + "Z";
const img = "https://images.example.com/a.jpg";

// ---------------------------------------------------------------------------
// Puras
// ---------------------------------------------------------------------------

Deno.test("safeImageUrl: solo https válido, sin credenciales, largo acotado", () => {
  assertEquals(safeImageUrl(img), img);
  assertEquals(safeImageUrl("http://images.example.com/a.jpg"), null);
  assertEquals(safeImageUrl("javascript:alert(1)"), null);
  assertEquals(safeImageUrl("https://user:pw@images.example.com/a.jpg"), null);
  assertEquals(safeImageUrl("https://localhost/a.jpg"), null);
  assertEquals(safeImageUrl("https://x.example.com/" + "a".repeat(600)), null);
  assertEquals(safeImageUrl(null), null);
  assertEquals(safeImageUrl(42), null);
});

Deno.test("parseArticles (GDELT): socialimage http o rara se descarta", () => {
  const out = parseArticles({
    articles: [
      { url: "https://www.reuters.com/a", title: "Apple sube con fuerza hoy", seendate: seen(1), language: "English", socialimage: img },
      { url: "https://www.cnbc.com/b", title: "Otra nota distinta sobre Apple", seendate: seen(2), language: "English", socialimage: "http://x.example.com/i.jpg" },
    ],
  }, allow);
  assertEquals(out.map((h) => h.image_url), [img, null]);
});

Deno.test("parseFinnhubNews: link redirect resuelto por el nombre del medio; medio ajeno fuera", () => {
  const out = parseFinnhubNews([
    { headline: "Apple launches device", source: "CNBC", url: "https://finnhub.io/api/news?id=1", datetime: unix(3), image: img },
    { headline: "Apple from a blog", source: "Seeking Alpha", url: "https://finnhub.io/api/news?id=2", datetime: unix(3), image: img },
    { headline: "Apple on Yahoo", source: "Yahoo", url: "https://finnhub.io/api/news?id=3", datetime: unix(4), image: "http://insecure.example.com/x.jpg" },
    { headline: "Apple direct link", source: "Whatever", url: "https://www.reuters.com/x", datetime: unix(5), image: "" },
    { headline: "", source: "CNBC", url: "https://finnhub.io/api/news?id=4", datetime: unix(5) },
  ], allow);
  assertEquals(out.map((h) => h.domain), ["cnbc.com", "finance.yahoo.com", "reuters.com"]);
  assertEquals(out.map((h) => h.image_url), [img, null, null]);
  assertEquals(out[0].source, "CNBC");
});

Deno.test("parseYahooNews: exige que la nota nombre al símbolo y toma el thumbnail", () => {
  const out = parseYahooNews({
    news: [
      {
        title: "BTC jumps", publisher: "Reuters", link: "https://finance.yahoo.com/news/btc-1.html", providerPublishTime: unix(1),
        relatedTickers: ["BTC-USD"], thumbnail: { resolutions: [{ url: "https://s.yimg.com/o.jpg", width: 4000 }, { url: "https://s.yimg.com/m.jpg", width: 500 }] },
      },
      { title: "Other coin", publisher: "Reuters", link: "https://finance.yahoo.com/news/eth.html", providerPublishTime: unix(1), relatedTickers: ["ETH-USD"] },
      { title: "Unknown outlet", publisher: "Blog", link: "https://blog.example.com/x", providerPublishTime: unix(1), relatedTickers: ["BTC-USD"] },
    ],
  }, allow, "BTC-USD");
  assertEquals(out.length, 1);
  assertEquals(out[0].image_url, "https://s.yimg.com/m.jpg");
});

Deno.test("allowedDomainFor, dedupeHeadlines e isUsPlainSymbol", () => {
  assertEquals(allowedDomainFor("https://finnhub.io/api/news?id=1", "Infobae", allow), "infobae.com");
  assertEquals(allowedDomainFor("https://finnhub.io/api/news?id=1", "Y", allow), null);
  const h = (title: string, url: string, hrs: number) => ({
    title, url, source: "Reuters", domain: "reuters.com", published_at: new Date(Date.now() - hrs * 3600_000).toISOString(), language: "en" as const,
  });
  assertEquals(dedupeHeadlines([h("Apple unveils the new phone today", "https://a/1", 3), h("Apple unveils the new phone today!", "https://a/2", 2), h("Same url", "https://a/1", 1)]).map((x) => x.title), ["Same url", "Apple unveils the new phone today!"]);
  for (const s of ["AAPL", "BRK-B", "BRK.B", "MELI"]) assert(isUsPlainSymbol(s), s);
  for (const s of ["GGAL.BA", "BTC-USD", "AL30", "TOOLONGX", "7203.T"]) assertFalse(isUsPlainSymbol(s), s);
});

// ---------------------------------------------------------------------------
// headlinesByTicker con fuentes falsas
// ---------------------------------------------------------------------------

const names: Record<string, string> = {
  AAPL: "Apple Inc.", NVDA: "NVIDIA CORP", MELI: "MERCADOLIBRE INC", GGAL: "Grupo Financiero Galicia SA", YPF: "YPF SOCIEDAD ANONIMA",
};
const usSymbols = Object.keys(names);
const all = [...usSymbols, "GGAL.BA", "BTC-USD"];

async function setup() {
  for (const [ticker, title] of Object.entries(names)) {
    await db.from("sec_ticker_cik").upsert({ ticker, cik: String(1000 + usSymbols.indexOf(ticker)).padStart(10, "0"), title, refreshed_at: new Date().toISOString() });
  }
  await db.from("upstream_rate_gate").upsert({ source: "gdelt", next_allowed_at: new Date(Date.now() - 1000).toISOString() });
  await db.from("data_source_cache").delete().eq("cache_key", gdeltBreakerKey);
}
const cleanup = () => db.from("data_source_cache").delete().eq("cache_key", gdeltBreakerKey);
const randomDay = () => `2${String(Math.floor(Math.random() * 900) + 100)}-0${1 + Math.floor(Math.random() * 9)}-1${Math.floor(Math.random() * 9)}`;

type Sources = {
  gdelt: () => Response;
  finnhub: (symbol: string) => Response;
  yahoo: (symbol: string) => Response;
};
const finnhubRows = (symbol: string) => [
  { headline: `${symbol} reports news number one`, source: "Reuters", url: `https://finnhub.io/api/news?id=${symbol}1`, datetime: unix(3), image: img },
];
const yahooRows = (symbol: string) => ({
  news: [{
    title: `${symbol} moves on market news`, publisher: "Yahoo Finance", link: `https://finance.yahoo.com/news/${symbol}.html`,
    providerPublishTime: unix(2), relatedTickers: [symbol], thumbnail: { resolutions: [{ url: img, width: 300 }] },
  }],
});

function router(s: Sources) {
  return fakeFetch((url) => {
    if (url.includes("gdeltproject")) return s.gdelt();
    if (url.includes("finnhub.io/api/v1/company-news")) return s.finnhub(new URL(url).searchParams.get("symbol")!);
    if (url.includes("v1/finance/search")) return s.yahoo(new URL(url).searchParams.get("q")!);
    return new Response("nope", { status: 404 });
  });
}
const env: Record<string, string> = { FINNHUB_API_KEY: "test-key", NEWS_FALLBACK_LICENSED: "1" };
const count = (f: ReturnType<typeof fakeFetch>, part: string) => f.calls.filter((c) => c.url.includes(part)).length;

Deno.test("cobertura con GDELT 429: Finnhub cubre EE. UU./CEDEAR y Yahoo cubre .BA y cripto", async () => {
  await setup();
  try {
    const f = router({
      gdelt: () => new Response("slow down", { status: 429 }),
      finnhub: (s) => Response.json(finnhubRows(s)),
      yahoo: (s) => Response.json(yahooRows(s)),
    });
    const day = randomDay();
    const r = await headlinesByTicker(deps(f.fetch, env), all, day);
    for (const s of all) {
      assertEquals(r.byTicker[s].length, 1, s);
      assertEquals(r.status[s], "ok", s);
      assertEquals(r.byTicker[s][0].image_url, img, s);
    }
    // EE. UU. por Finnhub (dominio resuelto por el medio), el resto por Yahoo.
    assertEquals(r.byTicker.AAPL[0].domain, "reuters.com");
    assertEquals(r.byTicker["BTC-USD"][0].domain, "finance.yahoo.com");
    assertEquals(count(f, "finnhub.io"), usSymbols.length);
    // El CEDEAR (.BA) se busca como su subyacente de EE. UU.: lo cubre Finnhub;
    // a Yahoo solo va lo que no tiene subyacente (cripto).
    assertEquals(count(f, "v1/finance/search"), 1);
    assertEquals(r.fallback, all.length - 1);
    assertEquals(r.fetched, 0);
    // El cortacircuitos quedó abierto: otro pedido no espera el turno de GDELT.
    const gdeltCalls = count(f, "gdeltproject");
    await headlinesByTicker(deps(f.fetch, env), ["AAPL"], randomDay());
    assertEquals(count(f, "gdeltproject"), gdeltCalls);
    // Y lo resuelto quedó en la caché del día: segunda vuelta sin pedidos.
    const calls = f.calls.length;
    const again = await headlinesByTicker(deps(f.fetch, env), all, day);
    assertEquals(f.calls.length, calls);
    assertEquals(again.byTicker.AAPL.length, 1);
  } finally {
    await cleanup();
  }
});

Deno.test("sin licencia (NEWS_FALLBACK_LICENSED ausente): nunca se llama a Finnhub ni a Yahoo", async () => {
  await setup();
  try {
    const f = router({
      gdelt: () => new Response("slow down", { status: 429 }),
      finnhub: (s) => Response.json(finnhubRows(s)),
      yahoo: (s) => Response.json(yahooRows(s)),
    });
    const r = await headlinesByTicker(deps(f.fetch, { FINNHUB_API_KEY: "test-key" }), all, randomDay());
    assertEquals(count(f, "finnhub.io"), 0);
    assertEquals(count(f, "v1/finance/search"), 0);
    assertEquals(r.fallback, 0);
  } finally {
    await cleanup();
  }
});

Deno.test("cobertura con GDELT vacío: respaldo por ticker; vacío en todos = ok sin notas (no falla)", async () => {
  await setup();
  try {
    const f = router({
      gdelt: () => Response.json({}),
      finnhub: (s) => Response.json(s === "AAPL" || s === "NVDA" ? finnhubRows(s) : []),
      yahoo: (s) => Response.json(s === "MELI" ? yahooRows(s) : { news: [] }),
    });
    const r = await headlinesByTicker(deps(f.fetch, env), all, randomDay());
    assertEquals(r.fetched, 1);
    assertEquals(r.byTicker.AAPL.length, 1);
    assertEquals(r.byTicker.NVDA.length, 1);
    assertEquals(r.byTicker.MELI.length, 1); // Finnhub vacío → Yahoo
    for (const s of ["YPF", "GGAL", "GGAL.BA", "BTC-USD"]) {
      assertEquals(r.byTicker[s], [], s);
      assertEquals(r.status[s], "ok", s); // se consultó y no hay: NO es "no se pudo"
    }
    // Finnhub no se pide para .BA ni cripto.
    assertFalse(f.calls.some((c) => c.url.includes("company-news") && /GGAL\.BA|BTC/.test(c.url)));
  } finally {
    await cleanup();
  }
});

Deno.test("GDELT con datos recientes: no se gasta Finnhub ni Yahoo", async () => {
  await setup();
  try {
    const f = router({
      gdelt: () => Response.json({ articles: [{ url: "https://www.reuters.com/a/apple-1", title: "Apple sube con fuerza hoy", seendate: seen(1), language: "English", socialimage: img }] }),
      finnhub: () => new Response("x", { status: 500 }),
      yahoo: () => new Response("x", { status: 500 }),
    });
    const r = await headlinesByTicker(deps(f.fetch, env), ["AAPL"], randomDay());
    assertEquals(r.byTicker.AAPL[0].image_url, img);
    assertEquals(r.fallback, 0);
    assertEquals(count(f, "finnhub.io") + count(f, "v1/finance/search"), 0);
  } finally {
    await cleanup();
  }
});

Deno.test("todo caído: sin dato = failed (reintento corto); con caché vencida se sirve lo último, también el de ayer", async () => {
  await setup();
  try {
    const f = router({
      gdelt: () => new Response("x", { status: 500 }),
      finnhub: () => new Response("x", { status: 500 }),
      yahoo: () => new Response("x", { status: 503 }),
    });
    const day = randomDay();
    const r = await headlinesByTicker(deps(f.fetch, env), ["AAPL", "BTC-USD"], day);
    assertEquals(r.status, { AAPL: "failed", "BTC-USD": "failed" });
    assertEquals(r.byTicker.AAPL, []);

    // Caché vencida (hace 3 h) de AAPL en el día, y de NVDA solo del día anterior.
    const old = deps(f.fetch, env, () => Date.now() - 3 * 3600_000);
    const item = (t: string) => ({ title: t, url: `https://www.reuters.com/${t.length}`, source: "Reuters", domain: "reuters.com", published_at: new Date().toISOString(), language: "en" as const });
    const day2 = randomDay();
    await writeCache(old, tickerKey("AAPL", day2), { name: "Apple", items: [item("Apple cached story one")], as_of: new Date().toISOString(), status: "ok" });
    const yesterday = new Date(Date.parse(`${day2}T00:00:00Z`) - 86400_000).toISOString().slice(0, 10);
    await writeCache(old, tickerKey("NVDA", yesterday), { name: "NVIDIA", items: [item("Nvidia yesterday story")], as_of: new Date().toISOString(), status: "ok" });
    await db.from("data_source_cache").delete().eq("cache_key", gdeltBreakerKey);
    const r2 = await headlinesByTicker(deps(f.fetch, env), ["AAPL", "NVDA", "YPF"], day2);
    assertEquals(r2.byTicker.AAPL.map((h) => h.title), ["Apple cached story one"]);
    assertEquals(r2.byTicker.NVDA.map((h) => h.title), ["Nvidia yesterday story"]);
    assertEquals(r2.status, { AAPL: "ok", NVDA: "ok", YPF: "failed" });
  } finally {
    await cleanup();
  }
});

// ---------------------------------------------------------------------------
// daily-brief: estado del feed e imagen
// ---------------------------------------------------------------------------

const today = () => new Date().toISOString().slice(0, 10);
const rnd = () => "QZ" + Array.from({ length: 3 }, () => String.fromCharCode(65 + Math.floor(Math.random() * 26))).join("");

async function withBrief<T>(users: string[], fn: () => Promise<T>): Promise<T> {
  const { data } = await db.from("app_config").select("value").eq("key", "daily_brief").single();
  await db.from("app_config").update({ value: { ...(data!.value as object), percent: 0, users } }).eq("key", "daily_brief");
  try {
    return await fn();
  } finally {
    await db.from("app_config").update({ value: data!.value }).eq("key", "daily_brief");
  }
}
const get = (jwt: string, q: string) =>
  new Request(`http://local/functions/v1/daily-brief?${q}`, { headers: { Authorization: `Bearer ${jwt}` } });

Deno.test("daily-brief feed: mine_status ok con image_url, empty si se consultó sin notas, unavailable si no se pudo", async () => {
  await setup();
  try {
    const u = await createUser("premium");
    const cases: { name: string; src: Sources; status: string }[] = [
      {
        name: "con notas",
        status: "ok",
        src: { gdelt: () => Response.json({}), finnhub: (s) => Response.json(finnhubRows(s)), yahoo: () => Response.json({ news: [] }) },
      },
      {
        name: "consultado sin notas",
        status: "empty",
        src: { gdelt: () => Response.json({}), finnhub: () => Response.json([]), yahoo: () => Response.json({ news: [] }) },
      },
      {
        name: "no se pudo consultar",
        status: "unavailable",
        src: { gdelt: () => new Response("x", { status: 500 }), finnhub: () => new Response("x", { status: 500 }), yahoo: () => new Response("x", { status: 500 }) },
      },
    ];
    await withBrief([u.id], async () => {
      for (const c of cases) {
        await db.from("positions").delete().eq("user_id", u.id);
        const sym = rnd();
        await addPosition(u.id, sym);
        await db.from("data_source_cache").delete().eq("cache_key", gdeltBreakerKey);
        const f = router(c.src);
        const d = deps(f.fetch, env);
        const res = await handle(get(u.jwt, `scope=feed&lang=es&day=${today()}`), d);
        await d.settle();
        assertEquals(res.status, 200, c.name);
        const b = await res.json();
        assertEquals(b.mine_status, c.status, c.name);
        if (c.status === "ok") {
          assertEquals(b.mine.length, 1);
          assertEquals(b.mine[0].image_url, img);
          assertEquals(b.mine[0].ticker, sym);
        } else {
          assertEquals(b.mine, [], c.name);
        }
      }
    });
  } finally {
    await cleanup();
  }
});

Deno.test("daily-brief feed: pieces.images = false saca las fotos sin desplegar", async () => {
  await setup();
  try {
    const u = await createUser("premium");
    const sym = rnd();
    await addPosition(u.id, sym);
    await withBrief([u.id], async () => {
      const { data } = await db.from("app_config").select("value").eq("key", "daily_brief").single();
      const value = data!.value as { pieces?: Record<string, boolean> };
      await db.from("app_config").update({ value: { ...value, pieces: { ...(value.pieces ?? {}), images: false } } })
        .eq("key", "daily_brief");
      await db.from("data_source_cache").delete().eq("cache_key", gdeltBreakerKey);
      const f = router({ gdelt: () => Response.json({}), finnhub: (s) => Response.json(finnhubRows(s)), yahoo: () => Response.json({ news: [] }) });
      const d = deps(f.fetch, env);
      const b = await (await handle(get(u.jwt, `scope=feed&lang=es&day=${today()}`), d)).json();
      await d.settle();
      assertEquals(b.mine.length, 1);
      assertEquals(b.mine[0].image_url, undefined);
    });
  } finally {
    await cleanup();
  }
});

Deno.test("daily-brief feed: Free no recibe mine_status ni imágenes (solo el conteo)", async () => {
  const u = await createUser("free");
  await addPosition(u.id, rnd());
  await withBrief([u.id], async () => {
    const d = deps(fakeFetch(() => new Response("x", { status: 500 })).fetch, env);
    const b = await (await handle(get(u.jwt, `scope=feed&day=${today()}`), d)).json();
    await d.settle();
    assertEquals(b.mine, []);
    assertEquals(b.mine_status, undefined);
    assert(b.locked !== null);
  });
});

Deno.test("daily-brief topic: topic_news_status y image_url de GDELT; caído sin caché = unavailable", async () => {
  await setup();
  try {
    const u = await createUser("premium");
    const { data: topic } = await db.from("news_topics").select("id").eq("enabled", true).limit(1).single();
    await withBrief([u.id], async () => {
      const ok = router({
        gdelt: () => Response.json({ articles: [{ url: "https://www.reuters.com/t/1", title: "Topic story about markets", seendate: seen(1), language: "English", socialimage: img }] }),
        finnhub: () => new Response("x", { status: 500 }), yahoo: () => new Response("x", { status: 500 }),
      });
      const d = deps(ok.fetch, env);
      const day = today();
      await db.from("data_source_cache").delete().eq("cache_key", `gdelt:topic:${topic!.id}:${day}`);
      const b = await (await handle(get(u.jwt, `scope=topic&topic=${topic!.id}&day=${day}`), d)).json();
      await d.settle();
      assertEquals(b.topic_news_status, "ok");
      assertEquals(b.topic_news[0].image_url, img);

      await db.from("data_source_cache").delete().eq("cache_key", `gdelt:topic:${topic!.id}:${day}`);
      await db.from("upstream_rate_gate").upsert({ source: "gdelt", next_allowed_at: new Date(Date.now() - 1000).toISOString() });
      const down = deps(fakeFetch(() => new Response("x", { status: 500 })).fetch, env);
      const b2 = await (await handle(get(u.jwt, `scope=topic&topic=${topic!.id}&day=${day}`), down)).json();
      assertEquals(b2.topic_news_status, "unavailable");
      assertEquals(b2.topic_news, []);
    });
  } finally {
    await cleanup();
  }
});

// headlines: titulares de GDELT filtrados por la lista de medios permitidos.
// Base local real; GDELT reemplazado por una respuesta ArtList con la forma
// documentada (articles: url, title, seendate, domain, language).

import { assert, assertEquals } from "jsr:@std/assert@1";
import { handle } from "../headlines/handler.ts";
import { assignByName, gdeltUrl, parseArticles } from "../_shared/gdelt.ts";
import { addPosition, createUser, db, deps, fakeFetch, withNewsProvider } from "./helpers.ts";

const allow = new Map([["reuters.com", "Reuters"], ["infobae.com", "Infobae"], ["cnbc.com", "CNBC"]]);

const artList = {
  articles: [
    { url: "https://www.reuters.com/a", title: "Nvidia unveils new AI chip", seendate: "20261010T140000Z", domain: "reuters.com", language: "English", socialimage: "https://img/x.jpg" },
    { url: "https://www.infobae.com/b", title: "Apple y Nvidia lideran la suba en Wall Street", seendate: "20261009T120000Z", domain: "infobae.com", language: "Spanish" },
    { url: "https://www.cnbc.com/c", title: "Nvidia unveils new AI chip!", seendate: "20261010T150000Z", domain: "cnbc.com", language: "English" },
    { url: "https://spam.example/d", title: "Nvidia to the moon", seendate: "20261010T160000Z", domain: "spam.example", language: "English" },
    { url: "https://www.reuters.com/e", title: "Apple raises dividend", seendate: "20261008T100000Z", domain: "reuters.com", language: "English" },
    { url: "https://www.reuters.com/f", title: "", seendate: "20261008T100000Z", domain: "reuters.com", language: "English" },
  ],
};

Deno.test("parseArticles: solo medios permitidos, sin repetidos, sin imágenes, más nuevo primero", () => {
  const list = parseArticles(artList, allow);
  assertEquals(list.map((h) => h.url), ["https://www.reuters.com/a", "https://www.infobae.com/b", "https://www.reuters.com/e"]);
  assert(list.every((h) => !("socialimage" in h)));
  assertEquals(list[1].language, "es");
  assertEquals(list[0].published_at, "2026-10-10T14:00:00Z");
});

Deno.test("assignByName: cada titular va con la empresa que nombra", () => {
  const by = assignByName(parseArticles(artList, allow), { NVDA: "Nvidia", AAPL: "Apple" });
  assertEquals(by.NVDA.map((h) => h.url), ["https://www.reuters.com/a", "https://www.infobae.com/b"]);
  assertEquals(by.AAPL.map((h) => h.url), ["https://www.infobae.com/b", "https://www.reuters.com/e"]);
});

Deno.test("gdeltUrl: nombres con OR y ventana del informe", () => {
  const url = new URL(gdeltUrl(["Nvidia", "Mercado Libre"], ["reuters.com", "bloomberg.com", "finance.yahoo.com"], {
    from: new Date("2026-10-05T00:00:00Z"),
    to: new Date("2026-10-10T00:00:00Z"),
  }));
  // Solo los permitidos que GDELT indexa bien (con los 28 la rechaza por larga).
  assertEquals(
    url.searchParams.get("query"),
    '(Nvidia OR "Mercado Libre") (domain:reuters.com OR domain:yahoo.com) (sourcelang:english OR sourcelang:spanish)',
  );
  assertEquals(url.searchParams.get("maxrecords"), "250");
  assertEquals(url.searchParams.get("startdatetime"), "20261005000000");
  assertEquals(url.searchParams.get("mode"), "ArtList");
});

const req = (jwt: string | null, qs: string) =>
  new Request(`http://local/functions/v1/headlines?${qs}`, { headers: jwt ? { Authorization: `Bearer ${jwt}` } : {} });

Deno.test("headlines: Premium 403; Gold recibe titulares de la allowlist y el segundo pedido sale de la caché", async () => {
  await db.from("upstream_rate_gate").delete().eq("source", "gdelt");
  const premium = await createUser("premium");
  const gold = await createUser("gold");
  const f = fakeFetch(() => Response.json(artList));
  const d = deps(f.fetch);
  const tag = crypto.randomUUID().slice(0, 4).toUpperCase();
  const qs = `tickers=NV${tag},AP${tag}&names=Nvidia|Apple`;

  assertEquals((await handle(req(premium.jwt, qs), d)).status, 403);
  const r = await handle(req(gold.jwt, qs), d);
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.status, "ok");
  const domains = Object.values(body.by_ticker).flat().map((h) => (h as { domain: string }).domain);
  assert(domains.length >= 3);  // AAPL comparte el de Infobae
  assert(domains.every((x) => ["reuters.com", "infobae.com", "cnbc.com"].includes(x)));
  assertEquals(f.calls.length, 1);

  const again = await handle(req(gold.jwt, qs), d);
  assertEquals(again.headers.get("x-cache"), "hit");
  await again.body?.cancel();
  assertEquals(f.calls.length, 1);
});

Deno.test("headlines: GDELT limitado (429) → error controlado, o el dato viejo si lo hay", async () => {
  await db.from("upstream_rate_gate").delete().eq("source", "gdelt");
  const gold = await createUser("gold");
  const f = fakeFetch(() => new Response("Please limit requests to one every 5 seconds", { status: 429 }));
  const r = await handle(req(gold.jwt, `tickers=Z${crypto.randomUUID().slice(0, 4).toUpperCase()}`), deps(f.fetch));
  assertEquals(r.status, 502);
  assertEquals((await r.json()).error.type, "upstream_unavailable");
});

Deno.test("headlines Premium: 200 con tickers en cartera (v2), 403 plan_required con uno ajeno", async () => {
  await db.from("upstream_rate_gate").delete().eq("source", "gdelt");
  const premium = await createUser("premium");
  const tag = crypto.randomUUID().slice(0, 3).toUpperCase();
  const held = `H${tag}`;
  const heldBa = `G${tag}.BA`;
  const heldUsd = `B${tag}-USD`;
  const foreign = `X${tag}`;
  for (const t of [held, heldBa, heldUsd]) await addPosition(premium.id, t);
  const f = fakeFetch(() => Response.json(artList));
  const d = deps(f.fetch);

  await withNewsProvider("v2", async () => {
    // Propios, incluidos los que se normalizan distinto (.BA, -USD → .USD).
    const own = await handle(req(premium.jwt, `tickers=${held},${heldBa},${heldUsd}&names=Nvidia|Apple|Bitcoin`), d);
    assertEquals(own.status, 200);
    assertEquals((await own.json()).status, "ok");
    assertEquals(f.calls.length, 1);

    // Uno ajeno corta todo el pedido, con la forma de error de siempre.
    const mixed = await handle(req(premium.jwt, `tickers=${held},${foreign}&names=Nvidia|Apple`), d);
    assertEquals(mixed.status, 403);
    assertEquals((await mixed.json()).error, { type: "plan_required", message: "Gold required", required_plan: "gold" });
    const only = await handle(req(premium.jwt, `tickers=${foreign}&names=Apple`), d);
    assertEquals(only.status, 403);
    await only.body?.cancel();
    assertEquals(f.calls.length, 1);
  });

  // Con el camino legacy, ni lo propio.
  await withNewsProvider("legacy", async () => {
    const r = await handle(req(premium.jwt, `tickers=${held}&names=Nvidia`), d);
    assertEquals(r.status, 403);
    await r.body?.cancel();
  });
});

Deno.test("headlines: Free con el ticker en cartera sigue en 403; Gold no necesita cartera", async () => {
  await db.from("upstream_rate_gate").delete().eq("source", "gdelt");
  const free = await createUser("free");
  const gold = await createUser("gold");
  const t = `F${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  await addPosition(free.id, t);
  const f = fakeFetch(() => Response.json(artList));
  await withNewsProvider("v2", async () => {
    const r = await handle(req(free.jwt, `tickers=${t}&names=Nvidia`), deps(f.fetch));
    assertEquals(r.status, 403);
    await r.body?.cancel();
    const g = await handle(req(gold.jwt, `tickers=${t}&names=Nvidia`), deps(f.fetch));
    assertEquals(g.status, 200);
    await g.body?.cancel();
  });
});

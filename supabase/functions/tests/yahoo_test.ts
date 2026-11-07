import { assertEquals } from "jsr:@std/assert@1";
import { config, handle, resetSession } from "../yahoo/handler.ts";
import { createUser, deps, fakeFetch } from "./helpers.ts";

function req(jwt: string | null, pathAndQuery: string): Request {
  return new Request(`http://local/functions/v1/yahoo${pathAndQuery}`, {
    headers: jwt ? { Authorization: `Bearer ${jwt}` } : {},
  });
}

const holdingsBody = {
  quoteSummary: {
    result: [{ topHoldings: { holdings: [{ symbol: "JPM", holdingName: "JPMorgan", holdingPercent: { raw: 0.1 } }] } }],
    error: null,
  },
};

/// Yahoo falso: cookie en fc.yahoo.com, crumb en getcrumb y [summary] para
/// quoteSummary.
function yahoo(summary: (url: URL, n: number) => Response) {
  let summaryCalls = 0;
  return fakeFetch((u, init) => {
    if (u.startsWith(config.cookieUrl)) {
      return new Response("", { status: 404, headers: { "set-cookie": "A3=abc; Domain=.yahoo.com; Secure" } });
    }
    if (u.startsWith(config.crumbUrl)) {
      const cookie = new Headers(init?.headers).get("cookie");
      return new Response(cookie === "A3=abc" ? "crumb123" : "", { status: cookie ? 200 : 403 });
    }
    return summary(new URL(u), ++summaryCalls);
  });
}

const symbol = () => `E${crypto.randomUUID().slice(0, 5).toUpperCase().replace(/[^A-Z0-9]/g, "X")}`;

Deno.test("sin JWT → 401", async () => {
  const r = await handle(req(null, "/quote-summary?symbol=XLF&modules=topHoldings"), deps(yahoo(() => Response.json({})).fetch));
  assertEquals(r.status, 401);
});

Deno.test("endpoint o módulo fuera de la allowlist → error y Yahoo no se llama", async () => {
  resetSession();
  const user = await createUser();
  const f = yahoo(() => Response.json({}));
  const d = deps(f.fetch);
  assertEquals((await handle(req(user.jwt, "/v7/finance/quote?symbols=XLF"), d)).status, 404);
  assertEquals((await handle(req(user.jwt, "/quote-summary?symbol=XLF&modules=secFilings"), d)).status, 400);
  assertEquals((await handle(req(user.jwt, "/quote-summary?symbol=X%2FY&modules=topHoldings"), d)).status, 400);
  assertEquals(f.calls.length, 0);
});

Deno.test("manda cookie + crumb, y la caché compartida evita el segundo pedido (de otro usuario)", async () => {
  resetSession();
  const a = await createUser();
  const b = await createUser();
  const s = symbol();
  const f = yahoo(() => Response.json(holdingsBody));
  const d = deps(f.fetch);
  const first = await handle(req(a.jwt, `/quote-summary?symbol=${s}&modules=topHoldings,fundProfile`), d);
  assertEquals(first.headers.get("x-cache"), "miss");
  // Mismos módulos en otro orden → misma entrada de caché.
  const second = await handle(req(b.jwt, `/quote-summary?symbol=${s.toLowerCase()}&modules=fundProfile,topHoldings`), d);
  assertEquals(second.headers.get("x-cache"), "hit");
  assertEquals((await second.json()).quoteSummary.result[0].topHoldings.holdings[0].symbol, "JPM");

  const summaryCalls = f.calls.filter((c) => c.url.startsWith(config.quoteSummaryUrl));
  assertEquals(summaryCalls.length, 1);
  const sent = new URL(summaryCalls[0].url);
  assertEquals(sent.searchParams.get("crumb"), "crumb123");
  assertEquals(sent.searchParams.get("modules"), "fundProfile,topHoldings");
  assertEquals(new Headers(summaryCalls[0].init?.headers).get("cookie"), "A3=abc");
});

Deno.test("401 por crumb vencido: renueva la sesión y reintenta una vez", async () => {
  resetSession();
  const user = await createUser();
  const f = yahoo((_, n) =>
    n === 1 ? Response.json({ finance: { error: { code: "Unauthorized" } } }, { status: 401 }) : Response.json(holdingsBody)
  );
  const r = await handle(req(user.jwt, `/quote-summary?symbol=${symbol()}&modules=topHoldings`), deps(f.fetch));
  assertEquals(r.status, 200);
  assertEquals(f.calls.filter((c) => c.url.startsWith(config.crumbUrl)).length, 2);
});

Deno.test("429 de Yahoo: reintenta y, si sigue, sirve la caché vieja", async () => {
  resetSession();
  const user = await createUser();
  const s = symbol();
  let now = Date.now();
  const f = yahoo((_, n) => (n === 1 ? Response.json(holdingsBody) : new Response("Too Many Requests", { status: 429 })));
  const d = deps(f.fetch, {}, () => now);
  await handle(req(user.jwt, `/quote-summary?symbol=${s}&modules=topHoldings`), d);
  now += 25 * 60 * 60 * 1000; // vencida (24 h)
  const r = await handle(req(user.jwt, `/quote-summary?symbol=${s}&modules=topHoldings`), d);
  assertEquals(r.status, 200);
  assertEquals(r.headers.get("x-cache"), "stale");
  assertEquals(f.calls.filter((c) => c.url.startsWith(config.quoteSummaryUrl)).length, 1 + 1 + config.retryDelaysMs.length);
});

Deno.test("429 sin caché → error tipado; 404 de Yahoo pasa tal cual sin cachear", async () => {
  resetSession();
  const user = await createUser();
  const blocked = yahoo(() => new Response("Too Many Requests", { status: 429 }));
  const r = await handle(req(user.jwt, `/quote-summary?symbol=${symbol()}&modules=topHoldings`), deps(blocked.fetch));
  assertEquals(r.status, 502);
  assertEquals((await r.json()).error.type, "upstream_unavailable");

  resetSession();
  const s = symbol();
  const notFound = yahoo(() => Response.json({ quoteSummary: { result: null, error: { code: "Not Found" } } }, { status: 404 }));
  const d = deps(notFound.fetch);
  assertEquals((await handle(req(user.jwt, `/quote-summary?symbol=${s}&modules=topHoldings`), d)).status, 404);
  const again = await handle(req(user.jwt, `/quote-summary?symbol=${s}&modules=topHoldings`), d);
  assertEquals(again.headers.get("x-cache"), "miss");
});

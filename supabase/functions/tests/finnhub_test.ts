import { assertEquals } from "jsr:@std/assert@1";
import { config, handle } from "../finnhub/handler.ts";
import { createUser, db, deps, fakeFetch } from "./helpers.ts";

const env = { FINNHUB_API_KEY: "fh-server-key" };

function req(jwt: string | null, pathAndQuery: string): Request {
  return new Request(`http://local/functions/v1/finnhub${pathAndQuery}`, {
    headers: jwt ? { Authorization: `Bearer ${jwt}` } : {},
  });
}

Deno.test("sin JWT → 401", async () => {
  const r = await handle(req(null, "/stock/profile2?symbol=AAPL"), deps(fakeFetch(() => Response.json({})).fetch, env));
  assertEquals(r.status, 401);
});

Deno.test("endpoint fuera de la allowlist → 404 y Finnhub no se llama", async () => {
  const user = await createUser();
  const f = fakeFetch(() => Response.json({}));
  const r = await handle(req(user.jwt, "/crypto/candle?symbol=BTC"), deps(f.fetch, env));
  assertEquals(r.status, 404);
  assertEquals(f.calls.length, 0);
});

Deno.test("caché compartida: el segundo pedido igual (aunque sea de OTRO usuario) no llega a Finnhub", async () => {
  const a = await createUser();
  const b = await createUser();
  const symbol = `T${crypto.randomUUID().slice(0, 6)}`;
  const f = fakeFetch(() => Response.json({ name: "Test Corp" }));
  const d = deps(f.fetch, env);
  const first = await handle(req(a.jwt, `/stock/profile2?symbol=${symbol}`), d);
  assertEquals(first.headers.get("x-cache"), "miss");
  const second = await handle(req(b.jwt, `/stock/profile2?symbol=${symbol}&token=client-attempt`), d);
  assertEquals(second.headers.get("x-cache"), "hit");
  assertEquals((await second.json()).name, "Test Corp");
  assertEquals(f.calls.length, 1);
  // La key del servidor viaja a Finnhub; la del cliente se descarta.
  const sent = new URL(f.calls[0].url);
  assertEquals(sent.searchParams.get("token"), "fh-server-key");
});

Deno.test("vencido el TTL se vuelve a pedir", async () => {
  const user = await createUser();
  const symbol = `N${crypto.randomUUID().slice(0, 6)}`;
  let now = Date.now();
  const f = fakeFetch(() => Response.json([{ headline: "x" }]));
  const d = deps(f.fetch, env, () => now);
  await handle(req(user.jwt, `/company-news?symbol=${symbol}&from=2026-09-16&to=2026-09-30`), d);
  now += 11 * 60 * 1000; // noticias: 10 min
  await handle(req(user.jwt, `/company-news?symbol=${symbol}&from=2026-09-16&to=2026-09-30`), d);
  assertEquals(f.calls.length, 2);
});

Deno.test("429 de Finnhub: reintenta con backoff y, si sigue, sirve la caché vieja", async () => {
  const user = await createUser();
  const symbol = `R${crypto.randomUUID().slice(0, 6)}`;
  let now = Date.now();
  let calls = 0;
  const f = fakeFetch(() => {
    calls++;
    return calls === 1 ? Response.json({ metric: { peTTM: 11 } }) : new Response("slow down", { status: 429 });
  });
  const d = deps(f.fetch, env, () => now);
  await handle(req(user.jwt, `/stock/metric?symbol=${symbol}&metric=all`), d);
  now += 2 * 60 * 60 * 1000; // vencida (1 h)
  const r = await handle(req(user.jwt, `/stock/metric?symbol=${symbol}&metric=all`), d);
  assertEquals(r.status, 200);
  assertEquals(r.headers.get("x-cache"), "stale");
  assertEquals(calls, 1 + 1 + config.retryDelaysMs.length);
});

Deno.test("429 sin caché → error tipado, no cuelga el turno", async () => {
  const user = await createUser();
  const f = fakeFetch(() => new Response("slow down", { status: 429 }));
  const r = await handle(req(user.jwt, `/search?q=zz${crypto.randomUUID().slice(0, 4)}`), deps(f.fetch, env));
  assertEquals(r.status, 429);
  assertEquals((await r.json()).error.type, "upstream_unavailable");
  await db.from("finnhub_cache").select("cache_key").limit(1);
});

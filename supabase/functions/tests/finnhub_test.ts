import { assertEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { config, handle } from "../finnhub/handler.ts";
import { createUser, db, deps, fakeFetch } from "./helpers.ts";

const env = { FINNHUB_API_KEY: "fh-server-key" };

const asUser = (jwt: string) =>
  createClient(
    Deno.env.get("API_URL") ?? Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321",
    Deno.env.get("ANON_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: `Bearer ${jwt}` } }, auth: { persistSession: false } },
  );

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
  const user = await createUser("gold");
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
  const user = await createUser("gold");
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

Deno.test("endpoints de Gold: Free y Premium → 403 plan_required y Finnhub no se llama", async () => {
  const f = fakeFetch(() => Response.json({ metric: {} }));
  const d = deps(f.fetch, env);
  for (const tier of ["free", "premium"] as const) {
    const user = await createUser(tier);
    for (const path of [
      "/stock/metric?symbol=AAPL&metric=all",
      "/company-news?symbol=AAPL&from=2026-09-16&to=2026-09-30",
      "/stock/earnings?symbol=AAPL",
      "/calendar/earnings?symbol=AAPL&from=2026-09-16&to=2026-09-30",
      "/calendar/earnings?from=2026-09-16&to=2026-09-30",
    ]) {
      const r = await handle(req(user.jwt, path), d);
      assertEquals(r.status, 403, `${tier} ${path}`);
      const body = await r.json();
      assertEquals(body.error.type, "plan_required");
      assertEquals(body.error.required_plan, "gold");
    }
  }
  assertEquals(f.calls.length, 0);
});

Deno.test("endpoints de Gold: Gold pasa; profile2 y search siguen abiertos para Free", async () => {
  const symbol = `G${crypto.randomUUID().slice(0, 6)}`;
  const f = fakeFetch(() => Response.json({ ok: true }));
  const d = deps(f.fetch, env);
  const gold = await createUser("gold");
  const metric = await handle(req(gold.jwt, `/stock/metric?symbol=${symbol}&metric=all`), d);
  assertEquals(metric.status, 200);
  const free = await createUser("free");
  const profile = await handle(req(free.jwt, `/stock/profile2?symbol=${symbol}`), d);
  assertEquals(profile.status, 200);
  const search = await handle(req(free.jwt, `/search?q=${symbol}`), d);
  assertEquals(search.status, 200);
});

Deno.test("endpoints de Gold: la cortesía semanal de Free abre solo ese ticker", async () => {
  const user = await createUser("free");
  // Como en la app: la cortesía la gasta el usuario con la RPC.
  const monday = new Date();
  monday.setUTCDate(monday.getUTCDate() - ((monday.getUTCDay() + 6) % 7));
  const consumed = await asUser(user.jwt).rpc("consume_weekly_free_analysis", {
    p_week_start: monday.toISOString().slice(0, 10),
    p_ticker: "AAPL",
  });
  assertEquals(consumed.data?.ok, true);
  const f = fakeFetch(() => Response.json({ metric: {} }));
  const d = deps(f.fetch, env);
  const own = await handle(req(user.jwt, "/stock/metric?symbol=aapl&metric=all"), d);
  assertEquals(own.status, 200);
  await own.body?.cancel();
  const other = await handle(req(user.jwt, "/stock/metric?symbol=MSFT&metric=all"), d);
  assertEquals(other.status, 403);
  await other.body?.cancel();
});

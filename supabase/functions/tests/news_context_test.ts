// news-context: búsqueda web de OpenAI (Responses API) para el contexto de
// noticias. Base local real; OpenAI reemplazado por una respuesta guardada
// con la forma de la Responses API (output: web_search_call + message con
// url_citation).

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { bullets, cacheKey, handle, mergeParts, type NewsContext, parseBody, partsOf, prompts } from "../news-context/handler.ts";
import { addPosition, createUser, db, deps, fakeFetch, withNewsProvider, withPlanLimit } from "./helpers.ts";

const env = { OPENAI_API_KEY: "sk-server" };

function req(jwt: string | null, body: unknown, turnId?: string): Request {
  return new Request("http://local/functions/v1/news-context", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}),
      ...(turnId ? { "x-porty-turn-id": turnId } : {}),
    },
    body: JSON.stringify(body),
  });
}

const responsesAnswer = (text: string) =>
  Response.json({
    id: "resp_1",
    output: [
      { type: "web_search_call", id: "ws_1", status: "completed", action: { type: "search" } },
      {
        type: "message",
        role: "assistant",
        content: [{
          type: "output_text",
          text,
          annotations: [
            { type: "url_citation", start_index: 0, end_index: 10, url: "https://www.reuters.com/tech/nvidia-1?utm_source=openai", title: "Nvidia sube" },
            { type: "url_citation", start_index: 11, end_index: 20, url: "https://www.cnbc.com/nvidia-2", title: "Nvidia y China" },
            { type: "url_citation", start_index: 21, end_index: 30, url: "https://www.infobae.com/economia/nvidia-3", title: "Nvidia en Wall Street" },
            { type: "url_citation", start_index: 31, end_index: 40, url: "https://random-blog.example/nvidia", title: "Blog" },
            { type: "url_citation", start_index: 41, end_index: 50, url: "https://www.reuters.com/tech/nvidia-1", title: "dup" },
          ],
        }],
      },
    ],
    usage: { input_tokens: 9_000, output_tokens: 300 },
  });

const answer = [
  "- Nvidia presentó un nuevo chip para centros de datos ([reuters.com](https://www.reuters.com/x)).",
  "- Las acciones subieron 4% en la semana.",
  "- Hay dudas por las restricciones de exportación a China.",
].join("\n");

async function turnRow(userId: string): Promise<string> {
  const turnId = `t-${crypto.randomUUID()}`;
  const { error } = await db.from("ai_turn_usage").insert({ turn_id: turnId, user_id: userId, tier: "gold", model: "gpt-test" });
  if (error) throw error;
  return turnId;
}

Deno.test("parseBody/cacheKey: 1-5 tickers o un tema; la clave ignora orden y signos", () => {
  assertEquals(parseBody({}), null);
  assertEquals(parseBody({ tickers: ["A", "B", "C", "D", "E", "F"] }), null);
  assertEquals(parseBody({ tickers: ["A", "B", "C", "D", "E"] })?.tickers.length, 5);
  const a = parseBody({ tickers: ["nvda", "amd"], question: "¿Qué pasó?" })!;
  const b = parseBody({ tickers: ["AMD", "NVDA"], question: "que paso" })!;
  assertEquals(cacheKey(a), cacheKey(b));
  assertEquals(a.lang, "es");
});

Deno.test("bullets: limpia marcadores de cita del texto", () => {
  assertEquals(bullets(answer)[0], "Nvidia presentó un nuevo chip para centros de datos.");
  assertEquals(bullets("SIN_NOVEDADES"), []);
});

Deno.test("bullets: listas numeradas, guiones largos, negritas y párrafos sin viñetas", () => {
  assertEquals(bullets("Resumen:\n1. **MSFT** (2026-10-13): Microsoft subió.\n2) GOOGL (2026-10-12): Alphabet cayó."), [
    "MSFT (2026-10-13): Microsoft subió.",
    "GOOGL (2026-10-12): Alphabet cayó.",
  ]);
  assertEquals(bullets("– Uno.\n— Dos."), ["Uno.", "Dos."]);
  assertEquals(bullets("Microsoft presentó resultados.\n\nAlphabet anunció recompras."), [
    "Microsoft presentó resultados.",
    "Alphabet anunció recompras.",
  ]);
});

Deno.test("prompts: con varias empresas pide ticker y fecha en cada viñeta y cubrir todas", () => {
  const b = parseBody({ tickers: ["MSFT", "GOOGL", "VOO"] })!;
  const { instructions } = prompts(b, "2026-10-15");
  assert(instructions.includes('"- MSFT (2026-10-15): ..."'));
  assert(instructions.includes("Cover EACH company"));
  assert(instructions.includes("8 bullets at most"));
  const one = prompts(parseBody({ tickers: ["MSFT"] })!, "2026-10-15").instructions;
  assert(one.includes("5 bullets at most"));
  assert(!one.includes("Cover EACH company"));
});

Deno.test("news-context: sin JWT 401; Free y Premium 403 sin llamar a OpenAI", async () => {
  const f = fakeFetch(() => responsesAnswer(answer));
  assertEquals((await handle(req(null, { tickers: ["NVDA"] }), deps(f.fetch, env))).status, 401);
  for (const tier of ["free", "premium"] as const) {
    const u = await createUser(tier);
    const r = await handle(req(u.jwt, { tickers: ["NVDA"] }), deps(f.fetch, env));
    assertEquals(r.status, 403);
    assertEquals((await r.json()).error.type, "plan_required");
  }
  assertEquals(f.calls.length, 0);
});

Deno.test("news-context Gold: web_search con medios permitidos, citas limpias, costo al turno y caché compartida", async () => {
  const a = await createUser("gold");
  const b = await createUser("gold");
  const turnId = await turnRow(a.id);
  const ticker = `N${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  const f = fakeFetch(() => responsesAnswer(answer));
  const d = deps(f.fetch, env);

  const r = await handle(req(a.jwt, { tickers: [ticker], names: { [ticker]: "Nvidia" } }, turnId), d);
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.status, "ok");
  assertEquals(body.summary.length, 3);
  assertEquals(body.citations.map((c: { url: string }) => c.url), [
    "https://www.reuters.com/tech/nvidia-1",
    "https://www.cnbc.com/nvidia-2",
    "https://www.infobae.com/economia/nvidia-3",
  ]);
  assertEquals(body.citations[2].source, "Infobae");

  const sent = f.calls[0];
  assertEquals(sent.url, "https://api.openai.com/v1/responses");
  const tool = (sent.body as { tools: Record<string, unknown>[] }).tools[0];
  assertEquals(tool.type, "web_search");
  assert((tool.filters as { allowed_domains: string[] }).allowed_domains.includes("reuters.com"));
  assertEquals(tool.user_location, { type: "approximate", country: "AR" });

  const { data: usage } = await db.from("ai_turn_usage").select("web_search_calls, web_search_cost_usd").eq("turn_id", turnId).single();
  assertEquals(usage!.web_search_calls, 1);
  // gpt-5-mini: 1 búsqueda (US$0,01) + 9.000 × 0,25/M + 300 × 2/M.
  assertEquals(Number(usage!.web_search_cost_usd), 0.01285);

  // Mismos tickers y mismos nombres (b83dfba los suma a la clave) → la entrada es compartida.
  const again = await handle(req(b.jwt, { tickers: [ticker], names: { [ticker]: "Nvidia" } }), d);
  assertEquals(again.headers.get("x-cache"), "hit");
  await again.body?.cancel();
  assertEquals(f.calls.length, 1);
});

Deno.test("news-context: una búsqueda por turno", async () => {
  const u = await createUser("gold");
  const turnId = await turnRow(u.id);
  const f = fakeFetch(() => responsesAnswer(answer));
  const d = deps(f.fetch, env);
  const first = await handle(req(u.jwt, { tickers: [`T${crypto.randomUUID().slice(0, 4).toUpperCase()}`] }, turnId), d);
  assertEquals(first.status, 200);
  await first.body?.cancel();
  const second = await handle(req(u.jwt, { tickers: [`T${crypto.randomUUID().slice(0, 4).toUpperCase()}`] }, turnId), d);
  assertEquals(second.status, 429);
  assertEquals((await second.json()).error.type, "turn_limit");
  assertEquals(f.calls.length, 1);
});

Deno.test("news-context: sin novedades → empty (y no inventa viñetas)", async () => {
  const u = await createUser("gold");
  const f = fakeFetch(() => responsesAnswer("SIN_NOVEDADES"));
  const r = await handle(req(u.jwt, { tickers: [`E${crypto.randomUUID().slice(0, 4).toUpperCase()}`] }), deps(f.fetch, env));
  const body = await r.json();
  assertEquals(body.status, "empty");
  assertEquals(body.summary, []);
  // Sin resumen no viajan fuentes (la app las mostraría bajo "no hay noticias").
  assertEquals(body.citations, []);
});

Deno.test("partsOf: sin pregunta, una parte por empresa (con su nombre); con pregunta, todo junto", () => {
  const b = parseBody({ tickers: ["MSFT", "GOOGL"], names: { MSFT: "Microsoft" } })!;
  const parts = partsOf(b);
  assertEquals(parts.map((p) => p.tickers), [["MSFT"], ["GOOGL"]]);
  assertEquals(parts[0].names, { MSFT: "Microsoft" });
  // Un nombre del cliente no comparte la entrada del ticker sin nombre (no
  // envenena la caché de los demás).
  assertNotEquals(cacheKey(parts[0]), cacheKey(parseBody({ tickers: ["MSFT"] })!));
  assertEquals(cacheKey(parts[1]), cacheKey(parseBody({ tickers: ["GOOGL"] })!));
  assertNotEquals(
    cacheKey(parseBody({ tickers: ["AAPL"], names: { AAPL: "Apple" } })!),
    cacheKey(parseBody({ tickers: ["AAPL"], names: { AAPL: "Tesla" } })!),
  );
  assertEquals(partsOf(parseBody({ tickers: ["MSFT", "GOOGL"], question: "¿Qué pasó?" })!).length, 1);
});

Deno.test("mergeParts: viñetas con ticker, citas intercaladas sin repetir, vacías afuera", () => {
  const part = (subject: string, summary: string[], urls: string[]): NewsContext => ({
    status: summary.length ? "ok" : "empty",
    subject,
    summary,
    citations: urls.map((url) => ({ title: url, url, source: "Reuters", domain: "reuters.com" })),
    as_of: "2026-10-15T00:00:00Z",
  });
  const merged = mergeParts([
    part("Microsoft (MSFT)", ["(2026-10-13): Subió.", "(2026-10-12): Anunció algo.", "(2026-10-11): Otro.", "(2026-10-10): Cuarto."], ["https://r.com/a", "https://r.com/b"]),
    part("Alphabet (GOOGL)", ["(2026-10-14): Bajó."], ["https://r.com/c", "https://r.com/a"]),
    part("Duolingo (DUOL)", [], []),
  ], ["MSFT", "GOOGL", "DUOL"], "2026-10-15T00:00:00Z");
  assertEquals(merged.status, "ok");
  assertEquals(merged.summary, [
    "MSFT (2026-10-13): Subió.",
    "MSFT (2026-10-12): Anunció algo.",
    "MSFT (2026-10-11): Otro.",
    "GOOGL (2026-10-14): Bajó.",
  ]);
  assertEquals(merged.citations.map((c) => c.url), ["https://r.com/a", "https://r.com/c", "https://r.com/b"]);
});

Deno.test("news-context sin pregunta: una búsqueda por empresa, en paralelo, y caché por empresa", async () => {
  const u = await createUser("gold");
  const a = `A${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  const b = `B${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  const f = fakeFetch(() => responsesAnswer(answer));
  const d = deps(f.fetch, env);

  const r = await handle(req(u.jwt, { tickers: [a, b], names: { [a]: "Alfa", [b]: "Beta" } }, await turnRow(u.id)), d);
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.status, "ok");
  assertEquals(f.calls.length, 2);
  assert(body.summary.some((l: string) => l.startsWith(a)));
  assert(body.summary.some((l: string) => l.startsWith(b)));

  // Otra consulta con una de esas empresas (mismo nombre): sale de caché, sin buscar.
  const again = await handle(req(u.jwt, { tickers: [b], names: { [b]: "Beta" } }, await turnRow(u.id)), d);
  assertEquals(again.headers.get("x-cache"), "hit");
  await again.body?.cancel();
  assertEquals(f.calls.length, 2);
});

const today = () => new Date().toISOString().slice(0, 10);

Deno.test("news-context: la unidad es una búsqueda sin caché (2 empresas = 2 unidades, 1 pedido)", async () => {
  const u = await createUser("gold");
  const a = `A${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  const b = `B${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  const f = fakeFetch(() => responsesAnswer(answer));
  const d = deps(f.fetch, env);

  const r = await handle(req(u.jwt, { tickers: [a, b], names: { [a]: "Alfa", [b]: "Beta" } }, await turnRow(u.id)), d);
  assertEquals(r.status, 200);
  await r.body?.cancel();
  const { data } = await db.from("news_context_usage").select("count, units").eq("user_id", u.id).eq("day", today()).single();
  assertEquals(data, { count: 1, units: 2 });

  // Con una empresa ya en caché, otro pedido con una nueva gasta 1 unidad.
  const c = `C${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  const again = await handle(req(u.jwt, { tickers: [a, c], names: { [a]: "Alfa", [c]: "Gama" } }, await turnRow(u.id)), d);
  assertEquals(again.status, 200);
  await again.body?.cancel();
  const { data: after } = await db.from("news_context_usage").select("count, units").eq("user_id", u.id).eq("day", today()).single();
  assertEquals(after, { count: 2, units: 3 });
});

Deno.test("news-context: tope mensual → 429 monthly_limit sin llamar a OpenAI", async () => {
  await withPlanLimit("gold", "news_context_per_month", 1, async () => {
    const u = await createUser("gold");
    const a = `A${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
    const b = `B${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
    const f = fakeFetch(() => responsesAnswer(answer));
    // 2 búsquedas sin caché no entran en 1 unidad al mes.
    const r = await handle(req(u.jwt, { tickers: [a, b], names: { [a]: "Alfa", [b]: "Beta" } }, await turnRow(u.id)), deps(f.fetch, env));
    assertEquals(r.status, 429);
    assertEquals((await r.json()).error.type, "monthly_limit");
    assertEquals(f.calls.length, 0);
    const { data } = await db.from("news_context_usage").select("count, units").eq("user_id", u.id).eq("day", today()).maybeSingle();
    assertEquals(data?.units ?? 0, 0);
  });
});

Deno.test("news-context: con el tope mensual agotado sirve la caché vencida si hay", async () => {
  await withPlanLimit("gold", "news_context_per_month", 1, async () => {
    const u = await createUser("gold");
    const t = `S${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
    const stale: NewsContext = {
      status: "ok",
      subject: t,
      summary: ["(2026-10-01): Dato viejo."],
      citations: [{ title: "Reuters", url: "https://www.reuters.com/old", source: "Reuters", domain: "reuters.com" }],
      as_of: "2026-10-01T00:00:00Z",
    };
    const old = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    await db.from("data_source_cache").upsert({ cache_key: cacheKey(parseBody({ tickers: [t] })!), body: stale, fetched_at: old });
    // Se gasta la única unidad del mes con otra empresa y después se pide la vencida.
    const other = `O${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
    const f = fakeFetch(() => responsesAnswer(answer));
    const d = deps(f.fetch, env);
    const first = await handle(req(u.jwt, { tickers: [other] }, await turnRow(u.id)), d);
    assertEquals(first.status, 200);
    await first.body?.cancel();
    const r = await handle(req(u.jwt, { tickers: [t] }, await turnRow(u.id)), d);
    assertEquals(r.status, 200);
    assertEquals(r.headers.get("x-cache"), "stale");
    assertEquals((await r.json()).summary, stale.summary);
    assertEquals(f.calls.length, 1);
  });
});

Deno.test("news-context: la booleana vieja news_context_hit también aplica el tope mensual", async () => {
  await withPlanLimit("gold", "news_context_per_month", 1, async () => {
    const u = await createUser("gold");
    assertEquals((await db.rpc("news_context_hit", { p_user_id: u.id })).data, true);
    assertEquals((await db.rpc("news_context_hit", { p_user_id: u.id })).data, false);
  });
});

Deno.test("news-context Premium: solo tickers en cartera y solo con news_provider v2", async () => {
  const u = await createUser("premium");
  const held = `H${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  const foreign = `X${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  await addPosition(u.id, held);
  const f = fakeFetch(() => responsesAnswer(answer));
  const d = deps(f.fetch, env);

  await withNewsProvider("legacy", async () => {
    const r = await handle(req(u.jwt, { tickers: [held] }), d);
    assertEquals(r.status, 403);
    await r.body?.cancel();
  });
  await withNewsProvider("v2", async () => {
    const own = await handle(req(u.jwt, { tickers: [held], names: { [held]: "Held" } }, await turnRow(u.id)), d);
    assertEquals(own.status, 200);
    assertEquals((await own.json()).status, "ok");
    assertEquals(f.calls.filter((c) => c.url.includes("openai")).length, 1);

    // Uno propio y uno ajeno: se corta el pedido entero.
    const mixed = await handle(req(u.jwt, { tickers: [held, foreign] }), d);
    assertEquals(mixed.status, 403);
    assertEquals((await mixed.json()).error, { type: "plan_required", message: "Gold required", required_plan: "gold" });
    // Solo el ajeno, y un tema sin ticker.
    const other = await handle(req(u.jwt, { tickers: [foreign] }), d);
    assertEquals(other.status, 403);
    await other.body?.cancel();
    const topic = await handle(req(u.jwt, { topic: "inflación en EE. UU." }), d);
    assertEquals(topic.status, 403);
    await topic.body?.cancel();
    assertEquals(f.calls.filter((c) => c.url.includes("openai")).length, 1);
  });
});

Deno.test("news-context Premium: tickers con sufijo (.BA, -USD) coinciden con la cartera", async () => {
  const u = await createUser("premium");
  const tag = crypto.randomUUID().slice(0, 3).toUpperCase();
  const ba = `G${tag}.BA`;
  const usd = `B${tag}-USD`;
  await addPosition(u.id, ba);
  await addPosition(u.id, usd.toLowerCase());
  const f = fakeFetch(() => responsesAnswer(answer));
  await withNewsProvider("v2", async () => {
    const r = await handle(req(u.jwt, { tickers: [ba, usd], names: { [ba]: "Galicia", [usd]: "Bitcoin" } }, await turnRow(u.id)), deps(f.fetch, env));
    assertEquals(r.status, 200);
    await r.body?.cancel();
  });
});

Deno.test("news-context Premium: el nombre que manda el cliente no entra en la búsqueda", async () => {
  const u = await createUser("premium");
  const held = `H${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  await addPosition(u.id, held);
  const f = fakeFetch((url) => url.includes("openai") ? responsesAnswer(answer) : new Response("{}", { status: 404 }));
  await withNewsProvider("v2", async () => {
    const r = await handle(req(u.jwt, { tickers: [held], names: { [held]: "Tesla" } }, await turnRow(u.id)), deps(f.fetch, env));
    assertEquals(r.status, 200);
    await r.body?.cancel();
  });
  const sent = f.calls.find((c) => c.url.includes("openai"))!;
  assert(!JSON.stringify(sent.body).includes("Tesla"));
});

Deno.test("news-context Premium: names y question del cliente se ignoran y la entrada compartida no se ensucia", async () => {
  const u = await createUser("premium");
  const held = `H${crypto.randomUUID().slice(0, 4).toUpperCase()}`;
  await addPosition(u.id, held);
  const f = fakeFetch((url) => url.includes("openai") ? responsesAnswer(answer) : new Response("{}", { status: 404 }));
  await withNewsProvider("v2", async () => {
    const r = await handle(
      req(u.jwt, { tickers: [held], names: { [held]: "Tesla" }, question: "¿Qué pasó con Tesla y su CEO?" }, await turnRow(u.id)),
      deps(f.fetch, env),
    );
    assertEquals(r.status, 200);
    await r.body?.cancel();
  });
  const sent = JSON.stringify(f.calls.find((c) => c.url.includes("openai"))!.body);
  assert(!sent.includes("Tesla"));
  // Se guardó en la clave sin pregunta (la que lee cualquiera), con el subject del servidor.
  const shared = cacheKey(parseBody({ tickers: [held] })!);
  const { data } = await db.from("data_source_cache").select("body").eq("cache_key", shared).single();
  assert(!JSON.stringify(data!.body).includes("Tesla"));
  // Ninguna otra entrada del ticker (ni con pregunta ni con nombre). Ojo: en
  // LIKE "_" es comodín, por eso se comparan las claves enteras.
  const { data: all } = await db.from("data_source_cache").select("cache_key").like("cache_key", `news:${held}|%`);
  assertEquals(all!.map((r) => r.cache_key), [shared]);
});

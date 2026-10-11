// news-context: búsqueda web de OpenAI (Responses API) para el contexto de
// noticias. Base local real; OpenAI reemplazado por una respuesta guardada
// con la forma de la Responses API (output: web_search_call + message con
// url_citation).

import { assert, assertEquals } from "jsr:@std/assert@1";
import { bullets, cacheKey, handle, parseBody } from "../news-context/handler.ts";
import { createUser, db, deps, fakeFetch } from "./helpers.ts";

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

Deno.test("parseBody/cacheKey: 1-3 tickers o un tema; la clave ignora orden y signos", () => {
  assertEquals(parseBody({}), null);
  assertEquals(parseBody({ tickers: ["A", "B", "C", "D"] }), null);
  const a = parseBody({ tickers: ["nvda", "amd"], question: "¿Qué pasó?" })!;
  const b = parseBody({ tickers: ["AMD", "NVDA"], question: "que paso" })!;
  assertEquals(cacheKey(a), cacheKey(b));
  assertEquals(a.lang, "es");
});

Deno.test("bullets: limpia marcadores de cita del texto", () => {
  assertEquals(bullets(answer)[0], "Nvidia presentó un nuevo chip para centros de datos.");
  assertEquals(bullets("SIN_NOVEDADES"), []);
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

  const again = await handle(req(b.jwt, { tickers: [ticker] }), d);
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
});

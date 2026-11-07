import { assertEquals } from "jsr:@std/assert@1";
import { handle, queryKey, withoutCiteMarkers } from "../web-search/handler.ts";
import { createUser, db, deps, fakeFetch, withPlanLimit } from "./helpers.ts";

const env = { OPENAI_API_KEY: "sk-server" };

function req(jwt: string | null, body: unknown): Request {
  return new Request("http://local/functions/v1/web-search", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}) },
    body: JSON.stringify(body),
  });
}

const openAiAnswer = (text: string) =>
  Response.json({
    status: "completed",
    output: [
      { type: "web_search_call", status: "completed" },
      {
        type: "message",
        content: [{
          type: "output_text",
          text,
          annotations: [
            { type: "url_citation", url: "https://www.apple.com/macbook-neo/", title: "MacBook Neo" },
            { type: "url_citation", url: "https://www.apple.com/macbook-neo/", title: "dup" },
          ],
        }],
      },
    ],
    usage: { input_tokens: 2000, output_tokens: 300 },
  });

Deno.test("sin JWT → 401 y OpenAI no se llama", async () => {
  const f = fakeFetch(() => openAiAnswer("x"));
  const r = await handle(req(null, { query: "precio macbook" }), deps(f.fetch, env));
  assertEquals(r.status, 401);
  assertEquals(f.calls.length, 0);
});

Deno.test("busca con la key del servidor, devuelve fuentes sin repetir y cachea para todos", async () => {
  const a = await createUser();
  const b = await createUser();
  const query = `precio MacBook Neo ${crypto.randomUUID().slice(0, 6)}`;
  const f = fakeFetch(() => openAiAnswer("La MacBook Neo cuesta 599 USD en EE. UU."));
  const d = deps(f.fetch, env);

  const first = await handle(req(a.jwt, { query }), d);
  assertEquals(first.status, 200);
  const body = await first.json();
  assertEquals(body.status, "ok");
  assertEquals(body.sources, [{ title: "MacBook Neo", url: "https://www.apple.com/macbook-neo/" }]);
  assertEquals((f.calls[0].init?.headers as Record<string, string>).Authorization, "Bearer sk-server");
  assertEquals(f.calls[0].url, "https://api.openai.com/v1/responses");
  assertEquals((f.calls[0].body as Record<string, unknown>).model, "gpt-6-luna");

  const second = await handle(req(b.jwt, { query: `  ${query.toUpperCase()} ` }), d);
  assertEquals(second.headers.get("x-cache"), "hit");
  assertEquals(f.calls.length, 1);
});

Deno.test("fuera de tema no se cachea como respuesta", async () => {
  const user = await createUser();
  const query = `receta de tallarines ${crypto.randomUUID().slice(0, 6)}`;
  const r = await handle(req(user.jwt, { query }), deps(fakeFetch(() => openAiAnswer("FUERA_DE_TEMA")).fetch, env));
  assertEquals((await r.json()).status, "off_topic");
  const { data } = await db.from("web_search_cache").select().eq("query_key", queryKey(query)).maybeSingle();
  assertEquals(data, null);
});

Deno.test("tope diario del plan (free = 3)", async () => {
  const user = await createUser("free");
  const f = fakeFetch(() => openAiAnswer("ok"));
  const d = deps(f.fetch, env);
  const statuses: number[] = [];
  for (let i = 0; i < 4; i++) {
    const r = await handle(req(user.jwt, { query: `precio ${crypto.randomUUID()}` }), d);
    statuses.push(r.status);
    await r.body?.cancel();
  }
  assertEquals(statuses, [200, 200, 200, 429]);
  assertEquals(f.calls.length, 3);
});

Deno.test("el texto sale sin marcadores de cita (las fuentes van aparte)", () => {
  assertEquals(
    withoutCiteMarkers("El iPhone 17 cuesta $799 USD. ([apple.com](https://www.apple.com/x?utm_source=openai))"),
    "El iPhone 17 cuesta $799 USD.",
  );
  assertEquals(withoutCiteMarkers("Según [Apple](https://apple.com), 799 USD."), "Según Apple, 799 USD.");
});

Deno.test("tope mensual del plan: 429 monthly_limit sin llamar a OpenAI, y la caché sigue sirviendo", async () => {
  await withPlanLimit("free", "web_searches_per_month", 2, async () => {
    const user = await createUser("free");
    const f = fakeFetch(() => openAiAnswer("ok"));
    const d = deps(f.fetch, env);
    const cachedQuery = `precio con caché ${crypto.randomUUID()}`;

    const first = await handle(req(user.jwt, { query: cachedQuery }), d);
    assertEquals(first.status, 200);
    await first.body?.cancel();
    const second = await handle(req(user.jwt, { query: `precio ${crypto.randomUUID()}` }), d);
    assertEquals(second.status, 200);
    await second.body?.cancel();
    assertEquals(f.calls.length, 2);

    const third = await handle(req(user.jwt, { query: `precio ${crypto.randomUUID()}` }), d);
    assertEquals(third.status, 429);
    assertEquals((await third.json()).error.type, "monthly_limit");
    assertEquals(f.calls.length, 2);

    // Un hit de caché no gasta cupo ni se corta.
    const hit = await handle(req(user.jwt, { query: cachedQuery }), d);
    assertEquals(hit.headers.get("x-cache"), "hit");
    await hit.body?.cancel();
    assertEquals(f.calls.length, 2);
  });
});

Deno.test("el tope diario sigue cortando con daily_limit (no monthly_limit)", async () => {
  const user = await createUser("free");
  const d = deps(fakeFetch(() => openAiAnswer("ok")).fetch, env);
  let last: Response | null = null;
  for (let i = 0; i < 4; i++) {
    last = await handle(req(user.jwt, { query: `precio ${crypto.randomUUID()}` }), d);
    if (i < 3) await last.body?.cancel();
  }
  assertEquals(last!.status, 429);
  assertEquals((await last!.json()).error.type, "daily_limit");
});

Deno.test("la booleana vieja web_search_hit también aplica el tope mensual", async () => {
  await withPlanLimit("free", "web_searches_per_month", 1, async () => {
    const user = await createUser("free");
    assertEquals((await db.rpc("web_search_hit", { p_user_id: user.id })).data, true);
    assertEquals((await db.rpc("web_search_hit", { p_user_id: user.id })).data, false);
  });
});

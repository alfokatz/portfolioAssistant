// news-compare (spec §3.6): gating por plan, interruptor, caché de 6 h, costo
// de 3 unidades y validador de atribución. Base local real; OpenAI falso.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { cacheKey, handle, normalizeStoryUrl, parseBody, prompts } from "../news-compare/handler.ts";
import { addPosition, createUser, db, deps, fakeFetch, withNewsProvider } from "./helpers.ts";

const env = { OPENAI_API_KEY: "sk-server" };

async function withBrief<T>(users: string[], fn: () => Promise<T>, extra: Record<string, unknown> = {}): Promise<T> {
  const { data } = await db.from("app_config").select("value").eq("key", "daily_brief").single();
  await db.from("app_config").update({ value: { ...(data!.value as object), percent: 0, users, ...extra } }).eq("key", "daily_brief");
  try {
    return await fn();
  } finally {
    await db.from("app_config").update({ value: data!.value }).eq("key", "daily_brief");
  }
}

function req(jwt: string | null, body: unknown, turnId?: string): Request {
  return new Request("http://local/functions/v1/news-compare", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}),
      ...(turnId ? { "x-porty-turn-id": turnId } : {}),
    },
    body: JSON.stringify(body),
  });
}

async function turnRow(userId: string): Promise<string> {
  const turnId = `t-${crypto.randomUUID()}`;
  const { error } = await db.from("ai_turn_usage").insert({ turn_id: turnId, user_id: userId, tier: "gold", model: "gpt-test" });
  if (error) throw error;
  return turnId;
}

/// Respuesta de la Responses API con viñetas etiquetadas y una cita por rango.
function answer(lines: { text: string; urls: { url: string; title: string }[] }[]) {
  let text = "";
  const annotations: unknown[] = [];
  for (const l of lines) {
    const start = text.length;
    text += l.text + "\n";
    for (const u of l.urls) {
      annotations.push({ type: "url_citation", start_index: start, end_index: start + l.text.length, url: u.url, title: u.title });
    }
  }
  return Response.json({
    output: [{ type: "web_search_call" }, { type: "message", content: [{ type: "output_text", text, annotations }] }],
    usage: { input_tokens: 5000, output_tokens: 400 },
  });
}

const reuters = { url: "https://www.reuters.com/tech/nvidia-lanza-nuevo-chip-2026-12-01/", title: "Nvidia lanza nuevo chip" };
const cnbc = { url: "https://www.cnbc.com/2026/12/01/nvidia-chip-data-centers.html", title: "Nvidia chip for data centers" };
const infobae = { url: "https://www.infobae.com/economia/2026/12/01/nvidia-chip-centros-de-datos/", title: "Nvidia y los centros de datos" };

const good = () =>
  answer([
    { text: "- [agree] Reuters y CNBC informan que Nvidia presentó un chip para centros de datos.", urls: [reuters, cnbc] },
    { text: "- [only] Según Infobae, el chip apunta a los centros de datos de la región.", urls: [infobae] },
  ]);

async function units(userId: string): Promise<{ count: number; units: number }> {
  const { data } = await db.from("news_context_usage").select("count, units").eq("user_id", userId);
  return { count: (data ?? []).reduce((n, r) => n + r.count, 0), units: (data ?? []).reduce((n, r) => n + r.units, 0) };
}

Deno.test("parseBody/cacheKey/normalizeStoryUrl: exactamente uno de ticker o tema; la URL se limpia", () => {
  assertEquals(parseBody({}), null);
  assertEquals(parseBody({ ticker: "NVDA", topic_id: "fed_rates" }), null);
  assertEquals(parseBody({ ticker: "nv dia" }), null);
  assertEquals(parseBody({ topic_id: "Fed Rates" }), null);
  assertEquals(parseBody({ ticker: "nvda", lang: "en" }), { ticker: "NVDA", topic_id: null, story_url: null, lang: "en" });
  const allow = new Map([["reuters.com", "Reuters"]]);
  assertEquals(normalizeStoryUrl("https://WWW.reuters.com/a-story-1/?utm_source=x#frag", allow), "https://www.reuters.com/a-story-1");
  // Dominio fuera de la allowlist o http: se ignora.
  assertEquals(normalizeStoryUrl("https://random.example/a-story-1", allow), "");
  assertEquals(normalizeStoryUrl("http://www.reuters.com/a-story-1", allow), "");
  assertEquals(cacheKey("NVDA", "", "es"), "compare:nvda||es");
  assert(prompts({ subject: "NVIDIA (NVDA)", storyUrl: "", lang: "es" }, "2026-12-02").instructions.includes("AT LEAST 3 DIFFERENT outlets"));
});

Deno.test("news-compare: 401, cuerpo inválido y 403 disabled con el interruptor apagado", async () => {
  const f = fakeFetch(() => good());
  assertEquals((await handle(req(null, { ticker: "NVDA" }), deps(f.fetch, env))).status, 401);
  const u = await createUser("gold");
  assertEquals((await handle(req(u.jwt, { ticker: "NVDA", topic_id: "fed_rates" }), deps(f.fetch, env))).status, 400);
  const off = await handle(req(u.jwt, { ticker: "NVDA" }), deps(f.fetch, env));
  assertEquals(off.status, 403);
  assertEquals((await off.json()).error.type, "disabled");
  await withBrief([u.id], async () => {
    // Pieza `compare` apagada: también 403.
    const { data } = await db.from("app_config").select("value").eq("key", "daily_brief").single();
    const pieces = { ...((data!.value as { pieces: object }).pieces), compare: false };
    await withBrief([u.id], async () => {
      assertEquals((await handle(req(u.jwt, { ticker: "NVDA" }), deps(f.fetch, env))).status, 403);
    }, { pieces });
  });
  assertEquals(f.calls.length, 0);
});

Deno.test("news-compare: gating por plan, sin llamar a OpenAI", async () => {
  const free = await createUser("free");
  const premium = await createUser("premium");
  await addPosition(free.id, "NVDA");
  await addPosition(premium.id, "NVDA");
  const f = fakeFetch(() => good());
  await withNewsProvider("v2", () =>
    withBrief([free.id, premium.id], async () => {
      const ask = async (u: { jwt: string }, body: unknown) => {
        const r = await handle(req(u.jwt, body), deps(f.fetch, env));
        return { status: r.status, body: await r.json() };
      };
      // Free: ticker en cartera → premium; ticker ajeno → gold; tema → gold.
      let r = await ask(free, { ticker: "NVDA" });
      assertEquals([r.status, r.body.error.type, r.body.error.required_plan], [403, "plan_required", "premium"]);
      r = await ask(free, { ticker: "TSLA" });
      assertEquals([r.status, r.body.error.required_plan], [403, "gold"]);
      r = await ask(free, { topic_id: "fed_rates" });
      assertEquals([r.status, r.body.error.required_plan], [403, "gold"]);
      // Premium: ticker ajeno y tema → gold.
      r = await ask(premium, { ticker: "TSLA" });
      assertEquals([r.status, r.body.error.required_plan], [403, "gold"]);
      r = await ask(premium, { topic_id: "fed_rates" });
      assertEquals([r.status, r.body.error.required_plan], [403, "gold"]);
      // Tema inexistente.
      const gold = await createUser("gold");
      await withBrief([gold.id], async () => {
        const bad = await handle(req(gold.jwt, { topic_id: "no_existe_x" }), deps(f.fetch, env));
        assertEquals([bad.status, (await bad.json()).error.type], [400, "invalid_topic"]);
      });
    }));
  assertEquals(f.calls.length, 0);
});

Deno.test("news-compare: un Free con informe semanal en curso o cortesía de un ticker no compara (403)", async () => {
  const free = await createUser("free");
  const f = fakeFetch(() => good());
  const weekStart = new Date(Date.now() - ((new Date().getUTCDay() + 6) % 7) * 86400_000).toISOString().slice(0, 10);
  await db.from("weekly_reports").insert({ user_id: free.id, week_start: weekStart, status: "generating" });
  await withNewsProvider("v2", () =>
    withBrief([free.id], async () => {
      for (const body of [{ ticker: "TSLA" }, { topic_id: "fed_rates" }]) {
        const r = await handle(req(free.jwt, body), deps(f.fetch, env));
        assertEquals([r.status, (await r.json()).error.type], [403, "plan_required"]);
      }
    }));
  assertEquals(f.calls.length, 0);
});

Deno.test("news-compare: Premium compara un ticker en cartera; un miss gasta 3 unidades y el hit no gasta nada", async () => {
  const u = await createUser("premium");
  await addPosition(u.id, "NVDA");
  const f = fakeFetch(() => good());
  await db.from("data_source_cache").delete().like("cache_key", "compare:nvda|%");
  await withNewsProvider("v2", () =>
    withBrief([u.id], async () => {
      const r = await handle(req(u.jwt, { ticker: "NVDA", lang: "es" }, await turnRow(u.id)), deps(f.fetch, env));
      assertEquals(r.status, 200);
      assertEquals(r.headers.get("x-cache"), "miss");
      const body = await r.json();
      assertEquals(body.status, "ok");
      assertEquals(body.points.map((p: { kind: string }) => p.kind), ["agree", "only"]);
      assertEquals(body.outlets.sort(), ["CNBC", "Infobae", "Reuters"]);
      // Cada punto con medio y link; agree con 2 o más medios.
      for (const p of body.points) {
        assert(p.source_ids.length >= 1);
        for (const id of p.source_ids) assert(body.sources[id].url.startsWith("https://") && body.sources[id].source);
      }
      assert(body.points[0].source_ids.length >= 2);
      assertEquals(await units(u.id), { count: 1, units: 3 });
      const sent = f.calls[0].body as { tools: { filters: { allowed_domains: string[] } }[] };
      assert(sent.tools[0].filters.allowed_domains.includes("reuters.com"));

      // Hit de caché (otro turno): sin OpenAI y sin gastar unidades.
      const again = await handle(req(u.jwt, { ticker: "nvda", lang: "es" }, await turnRow(u.id)), deps(f.fetch, env));
      assertEquals(again.headers.get("x-cache"), "hit");
      assertEquals((await again.json()).status, "ok");
      assertEquals(f.calls.length, 1);
      assertEquals(await units(u.id), { count: 1, units: 3 });
    }));
});

Deno.test("news-compare: Gold compara un tema; con un solo medio es insufficient_sources, se cobra y se cachea", async () => {
  const u = await createUser("gold");
  const one = () => answer([{ text: "- [only] Según Reuters, la Fed mantuvo las tasas sin cambios.", urls: [reuters] }]);
  const f = fakeFetch(() => one());
  await db.from("data_source_cache").delete().like("cache_key", "compare:topic:fed_rates|%");
  await withNewsProvider("v2", () =>
    withBrief([u.id], async () => {
      const r = await handle(req(u.jwt, { topic_id: "fed_rates", lang: "es" }, await turnRow(u.id)), deps(f.fetch, env));
      assertEquals(r.status, 200);
      const body = await r.json();
      assertEquals([body.status, body.points], ["insufficient_sources", []]);
      assertEquals(body.subject, "Fed y tasas");
      assertEquals((await units(u.id)).units, 3);
      const again = await handle(req(u.jwt, { topic_id: "fed_rates", lang: "es" }, await turnRow(u.id)), deps(f.fetch, env));
      assertEquals(again.headers.get("x-cache"), "hit");
      assertEquals(f.calls.length, 1);
    }));
});

Deno.test("news-compare: 1 búsqueda por turno (429 turn_limit) y 502 si OpenAI falla", async () => {
  const u = await createUser("gold");
  const f = fakeFetch(() => good());
  await db.from("data_source_cache").delete().like("cache_key", "compare:topic:inflation|%");
  await db.from("data_source_cache").delete().like("cache_key", "compare:topic:oil_energy|%");
  await withNewsProvider("v2", () =>
    withBrief([u.id], async () => {
      const turn = await turnRow(u.id);
      assertEquals((await handle(req(u.jwt, { topic_id: "inflation" }, turn), deps(f.fetch, env))).status, 200);
      const second = await handle(req(u.jwt, { topic_id: "oil_energy" }, turn), deps(f.fetch, env));
      assertEquals(second.status, 429);
      assertEquals((await second.json()).error.type, "turn_limit");
      const down = fakeFetch(() => new Response("boom", { status: 500 }));
      const r = await handle(req(u.jwt, { topic_id: "oil_energy" }, await turnRow(u.id)), deps(down.fetch, env));
      assertEquals([r.status, (await r.json()).error.type], [502, "upstream_failed"]);
    }));
});

import { assert, assertEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { config, handle } from "../ai-chat/handler.ts";
import { sha256Hex } from "../_shared/common.ts";
import { createUser, db, deps, fakeFetch, monthlyUsed } from "./helpers.ts";

const url = Deno.env.get("API_URL") ?? "http://127.0.0.1:54321";
const anonKey = Deno.env.get("ANON_KEY") ?? "";

/// Cliente con la sesión del usuario: las RPCs de la app usan auth.uid().
function asUser(jwt: string) {
  return createClient(url, anonKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
}

/// Lunes de la semana cerrada anterior (siempre dentro de la ventana válida).
function lastClosedMonday(): string {
  const d = new Date(Date.now() - 7 * 86_400_000);
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() - (day - 1));
  return d.toISOString().slice(0, 10);
}

const week = lastClosedMonday();

/// El informe arranca apagado (app_config); estos tests lo prenden.
async function setEnabled(enabled: boolean) {
  const { error } = await db.from("app_config").upsert({ key: "weekly_report", value: { enabled } });
  if (error) throw error;
}
await setEnabled(true);

async function claim(jwt: string, w = week) {
  const { data, error } = await asUser(jwt).rpc("claim_weekly_report", { p_week_start: w });
  if (error) throw error;
  return data as { state: string; courtesy?: boolean; attempt?: number; payload?: unknown };
}

// ---------------------------------------------------------------------------
// Claim / complete / fail
// ---------------------------------------------------------------------------

Deno.test("Gold: claim → in_progress para otro dispositivo → complete → ready", async () => {
  const user = await createUser("gold");
  assertEquals(await claim(user.jwt), { state: "claimed", courtesy: false, attempt: 1 });
  assertEquals((await claim(user.jwt)).state, "in_progress");

  const done = await asUser(user.jwt).rpc("complete_weekly_report", {
    p_week_start: week,
    p_payload: { headline: "Semana tranquila" },
  });
  assertEquals(done.data, { ok: true });
  const ready = await claim(user.jwt);
  assertEquals(ready.state, "ready");
  assertEquals(ready.payload, { headline: "Semana tranquila" });
});

Deno.test("Free: la primera vez es degustación; después, solo números", async () => {
  const user = await createUser("free");
  const first = await claim(user.jwt);
  assertEquals(first.state, "claimed");
  assertEquals(first.courtesy, true);

  // Otra semana: la degustación ya se usó.
  const other = await createUser("premium");
  await db.from("weekly_reports").insert({
    user_id: other.id,
    week_start: "2026-01-05",
    status: "ready",
    courtesy: true,
  });
  assertEquals((await claim(other.jwt)).state, "numbers_only");
  // Y no se crea fila para la variante de solo números.
  const { count } = await db.from("weekly_reports").select("*", { count: "exact", head: true })
    .eq("user_id", other.id).eq("week_start", week);
  assertEquals(count, 0);
});

Deno.test("semana inválida (futura, no lunes, muy vieja) → error", async () => {
  const user = await createUser("gold");
  for (const w of ["2030-01-07", "2026-09-22", "2025-01-06"]) {
    const { error } = await asUser(user.jwt).rpc("claim_weekly_report", { p_week_start: w });
    assert(error, w);
  }
});

Deno.test("fail libera el claim; al tercer intento queda failed", async () => {
  const user = await createUser("gold");
  const rpc = asUser(user.jwt);
  assertEquals((await claim(user.jwt)).attempt, 1);
  await rpc.rpc("fail_weekly_report", { p_week_start: week });
  assertEquals((await claim(user.jwt)).attempt, 2);
  await rpc.rpc("fail_weekly_report", { p_week_start: week });
  assertEquals((await claim(user.jwt)).attempt, 3);
  await rpc.rpc("fail_weekly_report", { p_week_start: week });
  assertEquals((await claim(user.jwt)).state, "failed");
});

Deno.test("una generación cortada se retoma pasado el TTL", async () => {
  const user = await createUser("gold");
  await claim(user.jwt);
  await db.from("weekly_reports")
    .update({ claimed_at: new Date(Date.now() - 3 * 60_000).toISOString() })
    .eq("user_id", user.id).eq("week_start", week);
  assertEquals((await claim(user.jwt)).state, "claimed");
});

Deno.test("complete exige un claim propio y un payload razonable", async () => {
  const user = await createUser("gold");
  const rpc = asUser(user.jwt);
  const noClaim = await rpc.rpc("complete_weekly_report", { p_week_start: week, p_payload: {} });
  assertEquals(noClaim.data, { ok: false, reason: "not_claimed" });
  await claim(user.jwt);
  const huge = await rpc.rpc("complete_weekly_report", {
    p_week_start: week,
    p_payload: { text: "x".repeat(70_000) },
  });
  assertEquals(huge.data, { ok: false, reason: "payload_too_large" });
  // Nadie escribe la tabla directo: solo por las RPCs.
  const direct = await rpc.from("weekly_reports").update({ status: "ready" }).eq("user_id", user.id).select();
  assertEquals(direct.data ?? [], []);
});

// ---------------------------------------------------------------------------
// ai-chat en modo informe
// ---------------------------------------------------------------------------

const reportPrompt = "Sos Porty. Escribí el informe semanal en JSON.";
const chatPrompt = "SYSTEM PROMPT DE LA APP v1";
const env = { OPENAI_API_KEY: "sk-server" };

function openAiOk() {
  return fakeFetch(() =>
    Response.json({
      choices: [{ message: { role: "assistant", content: '{"headline":"Semana tranquila"}' } }],
      usage: { prompt_tokens: 9000, completion_tokens: 800, prompt_tokens_details: { cached_tokens: 0 } },
    })
  );
}

function reportReq(
  jwt: string,
  body: Record<string, unknown>,
  { turnId = `rep-${crypto.randomUUID().slice(0, 12)}`, w = week, purpose = "weekly_report" } = {},
) {
  return new Request("http://local/functions/v1/ai-chat", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${jwt}`,
      "x-porty-turn-id": turnId,
      "x-porty-purpose": purpose,
      "x-porty-report-week": w,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

const reportBody = (extra: Record<string, unknown> = {}) => ({
  model: "gpt-4.1-mini",
  messages: [
    { role: "system", content: reportPrompt },
    { role: "user", content: '{"week":{}}' },
  ],
  ...extra,
});

async function options() {
  return {
    allowedPromptHashes: new Set([await sha256Hex(chatPrompt)]),
    allowedReportPromptHashes: new Set([await sha256Hex(reportPrompt)]),
  };
}

Deno.test("con claim: reenvía a OpenAI, NO cobra cuota y registra el costo como weekly_report", async () => {
  const user = await createUser("gold");
  await claim(user.jwt);
  const before = await monthlyUsed(user.id);
  const f = openAiOk();
  const turnId = `rep-${crypto.randomUUID().slice(0, 12)}`;
  const r = await handle(reportReq(user.jwt, reportBody({ max_completion_tokens: 9999 }), { turnId }), deps(f.fetch, env), await options());
  assertEquals(r.status, 200);
  assertEquals((await r.json()).choices[0].message.content, '{"headline":"Semana tranquila"}');
  assertEquals(await monthlyUsed(user.id), before);
  const sent = f.calls[0].body as Record<string, unknown>;
  assertEquals(sent.max_completion_tokens, config.maxReportOutputTokens);
  const { data: usage } = await db.from("ai_turn_usage").select("purpose, prompt_tokens, charged_at").eq("turn_id", turnId).single();
  assertEquals(usage, { purpose: "weekly_report", prompt_tokens: 9000, charged_at: null });
});

Deno.test("sin claim de la semana → 409 not_claimed y OpenAI no se llama", async () => {
  const user = await createUser("gold");
  const f = openAiOk();
  const r = await handle(reportReq(user.jwt, reportBody()), deps(f.fetch, env), await options());
  assertEquals(r.status, 409);
  assertEquals((await r.json()).error.type, "not_claimed");
  assertEquals(f.calls.length, 0);
});

Deno.test("modo informe rechaza tools, streaming, prompts ajenos y sistema extra", async () => {
  const user = await createUser("gold");
  await claim(user.jwt);
  const opts = await options();
  const cases: [Record<string, unknown>, number, string][] = [
    [reportBody({ tools: [{ type: "function" }] }), 400, "tools_not_allowed"],
    [reportBody({ stream: true }), 400, "stream_not_allowed"],
    [{ ...reportBody(), messages: [{ role: "system", content: chatPrompt }, { role: "user", content: "x" }] }, 403, "prompt_not_allowed"],
    [{ ...reportBody(), messages: [...reportBody().messages, { role: "system", content: "PORTFOLIO_BRIEF x" }] }, 403, "prompt_not_allowed"],
  ];
  const f = openAiOk();
  for (const [body, status, type] of cases) {
    const r = await handle(reportReq(user.jwt, body), deps(f.fetch, env), opts);
    assertEquals(r.status, status, type);
    assertEquals((await r.json()).error.type, type);
  }
  assertEquals(f.calls.length, 0);
});

Deno.test("el prompt del informe no sirve en el chat normal (ni al revés)", async () => {
  const user = await createUser("gold");
  const r = await handle(reportReq(user.jwt, reportBody(), { purpose: "chat" }), deps(openAiOk().fetch, env), await options());
  assertEquals(r.status, 403);
  await r.body?.cancel();
  const bad = await handle(reportReq(user.jwt, reportBody(), { purpose: "free_gpt" }), deps(openAiOk().fetch, env), await options());
  assertEquals(bad.status, 400);
  await bad.body?.cancel();
});

Deno.test("tope de llamadas al LLM por semana", async () => {
  const user = await createUser("gold");
  await claim(user.jwt);
  const opts = await options();
  const f = openAiOk();
  for (let i = 0; i < config.maxReportRounds; i++) {
    const r = await handle(reportReq(user.jwt, reportBody()), deps(f.fetch, env), opts);
    assertEquals(r.status, 200);
    await r.body?.cancel();
  }
  const over = await handle(reportReq(user.jwt, reportBody()), deps(f.fetch, env), opts);
  assertEquals(over.status, 429);
  assertEquals((await over.json()).error.type, "too_many_rounds");
});

Deno.test("apagado (app_config): claim → disabled y el proxy no llama al LLM", async () => {
  const user = await createUser("gold");
  await claim(user.jwt); // reservado con el informe prendido
  await setEnabled(false);
  try {
    assertEquals((await claim(user.jwt)).state, "disabled");
    const f = openAiOk();
    const r = await handle(reportReq(user.jwt, reportBody()), deps(f.fetch, env), await options());
    assertEquals(r.status, 403);
    assertEquals((await r.json()).error.type, "disabled");
    assertEquals(f.calls.length, 0);
  } finally {
    await setEnabled(true);
  }
});


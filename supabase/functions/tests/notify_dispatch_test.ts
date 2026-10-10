// notify-dispatch SIN red ni base: store en memoria (misma semántica que
// las RPCs de 20261011000000_push_notifications.sql, que cubre
// supabase/tests/push_notifications_db_test.sql) y FCM falso.
//
//   deno test --allow-env tests/notify_dispatch_test.ts

import { assert, assertEquals, assertMatch, assertStringIncludes } from "jsr:@std/assert@1";
import { decide, runDispatch } from "../notify-dispatch/dispatch.ts";
import { classify, type FcmMessage, FcmSender } from "../notify-dispatch/fcm.ts";
import { handle } from "../notify-dispatch/handler.ts";
import { localDate, quietEndsAt } from "../notify-dispatch/quiet.ts";
import type { OutboxRow, PushConfig } from "../notify-dispatch/store.ts";
import { render } from "../notify-dispatch/templates.ts";
import { FakeSender, MemoryDispatchStore } from "./push_fakes.ts";

// Mediodía de un martes en Buenos Aires (UTC-3).
const noonBA = Date.parse("2026-10-13T15:00:00Z");
// 23:30 en Buenos Aires.
const nightBA = Date.parse("2026-10-14T02:30:00Z");

// ── silencio ────────────────────────────────────────────────────────────────

Deno.test("silencio: cruza la medianoche y termina a las 08:00 locales", () => {
  const tz = "America/Argentina/Buenos_Aires";
  assertEquals(quietEndsAt(noonBA, tz, "22:00", "08:00"), null);
  assertEquals(quietEndsAt(nightBA, tz, "22:00", "08:00"), Date.parse("2026-10-14T11:00:00Z"));
  // Sin silencio (inicio == fin).
  assertEquals(quietEndsAt(nightBA, tz, "00:00", "00:00"), null);
  // Silencio que no cruza la medianoche: 13:00–15:00.
  assertEquals(quietEndsAt(noonBA, tz, "11:00", "13:00"), Date.parse("2026-10-13T16:00:00Z"));
  // Zona inválida: UTC.
  assertEquals(quietEndsAt(Date.parse("2026-10-13T23:00:00Z"), "Marte/Olympus", "22:00", "08:00"), Date.parse("2026-10-14T08:00:00Z"));
});

Deno.test("silencio: respeta el cambio de horario (Nueva York, noviembre)", () => {
  // 2026-11-01 es el cambio a EST: las 23:00 locales son 04:00Z.
  const t = Date.parse("2026-11-02T04:00:00Z");
  assertEquals(localDate(t, "America/New_York"), "2026-11-01");
  assertEquals(quietEndsAt(t, "America/New_York", "22:00", "08:00"), Date.parse("2026-11-02T13:00:00Z"));
});

// ── reglas ──────────────────────────────────────────────────────────────────

function ctxOf(store: MemoryDispatchStore, u: string) {
  return store.ctx.get(u);
}

Deno.test("reglas: interruptor, lista de prueba, tipo apagado, preferencias y plan", () => {
  const s = new MemoryDispatchStore(() => noonBA);
  s.user("u1");
  s.user("free", { tier: "free" });
  const row = (kind: string, user = "u1"): OutboxRow => ({
    id: 1, user_id: user, kind, dedupe_key: "x", data: {}, created_at: new Date(noonBA).toISOString(), attempts: 1,
  });
  const on: PushConfig = { enabled: true, allowUsers: [], kinds: {} };

  assertEquals(decide(row("big_move"), ctxOf(s, "u1"), { ...on, enabled: false }, noonBA), { action: "skip", reason: "push_disabled" });
  assertEquals(decide(row("big_move"), ctxOf(s, "u1"), { ...on, enabled: false, allowUsers: ["u1"] }, noonBA), { action: "send" });
  assertEquals(decide(row("big_move"), ctxOf(s, "u1"), { ...on, kinds: { big_move: false } }, noonBA), { action: "skip", reason: "kind_disabled" });
  assertEquals(decide(row("nuevo"), ctxOf(s, "u1"), on, noonBA), { action: "skip", reason: "unknown_kind" });
  assertEquals(decide(row("earnings_result"), ctxOf(s, "u1"), on, noonBA), { action: "skip", reason: "plan" });
  assertEquals(decide(row("big_move", "nadie"), undefined, on, noonBA), { action: "skip", reason: "no_devices" });

  s.user("u2", {}, { big_moves: false });
  assertEquals(decide(row("big_move", "u2"), ctxOf(s, "u2"), on, noonBA), { action: "skip", reason: "user_disabled_kind" });
  assertEquals(decide(row("portfolio_move", "u2"), ctxOf(s, "u2"), on, noonBA), { action: "send" });
  s.user("u3", {}, { enabled: false });
  assertEquals(decide(row("price_alert", "u3"), ctxOf(s, "u3"), on, noonBA), { action: "skip", reason: "user_disabled" });
  // La de prueba sale aunque el usuario apagó todo (la pidió él).
  assertEquals(decide(row("test", "u3"), ctxOf(s, "u3"), on, noonBA), { action: "send" });
});

Deno.test("reglas: en el silencio lo de mercado se descarta y el informe se corre", () => {
  const s = new MemoryDispatchStore(() => nightBA);
  s.user("u1");
  const on: PushConfig = { enabled: true, allowUsers: [], kinds: {} };
  const row = (kind: string): OutboxRow => ({
    id: 1, user_id: "u1", kind, dedupe_key: "x", data: {}, created_at: new Date(nightBA).toISOString(), attempts: 1,
  });
  assertEquals(decide(row("big_move"), ctxOf(s, "u1"), on, nightBA), { action: "skip", reason: "quiet_hours" });
  assertEquals(decide(row("weekly_report"), ctxOf(s, "u1"), on, nightBA), {
    action: "defer",
    reason: "quiet_hours",
    until: Date.parse("2026-10-14T11:00:00Z"),
  });
  // La alerta de precio también espera a la mañana (la pidió, pero no a
  // las 23:30).
  assertEquals(decide(row("price_alert"), ctxOf(s, "u1"), on, nightBA).action, "defer");
});

Deno.test("reglas: lo viejo no se manda", () => {
  const s = new MemoryDispatchStore(() => noonBA);
  s.user("u1");
  const row: OutboxRow = {
    id: 1, user_id: "u1", kind: "big_move", dedupe_key: "x", data: {},
    created_at: new Date(noonBA - 61 * 60_000).toISOString(), attempts: 1,
  };
  assertEquals(decide(row, ctxOf(s, "u1"), { enabled: true, allowUsers: [], kinds: {} }, noonBA), { action: "skip", reason: "stale" });
});

// ── despacho ────────────────────────────────────────────────────────────────

Deno.test("despacho: tope de 3 automáticas por día, y las alertas pasan primero", async () => {
  const s = new MemoryDispatchStore(() => noonBA);
  s.user("u1", { automaticLast24h: 1 });
  const moves = [s.add("u1", "big_move", { symbol: "A", change_pct: 6, weight_pct: 10 }),
    s.add("u1", "big_move", { symbol: "B", change_pct: -6, weight_pct: 10 }),
    s.add("u1", "big_move", { symbol: "C", change_pct: 7, weight_pct: 10 })];
  const alert = s.add("u1", "price_alert", { symbol: "VOO", condition: "above", target: 750, price: 751.2 });
  const sender = new FakeSender();

  const r = await runDispatch(s, sender, () => noonBA);
  assertEquals(r.sent, 3);
  assertEquals(r.skipped, { daily_cap: 1 });
  assertEquals(s.row(alert).status, "sent");
  assertEquals(sender.sent[0].data.kind, "price_alert");
  assertEquals(moves.map((id) => s.row(id).status), ["sent", "sent", "skipped"]);
});

Deno.test("despacho: un mensaje por dispositivo, en su idioma, y el token muerto se borra", async () => {
  const s = new MemoryDispatchStore(() => noonBA);
  s.user("u1", {
    devices: [
      { id: "d-es", token: "tok-es", platform: "ios", locale: "es", timezone: "America/Argentina/Buenos_Aires" },
      { id: "d-en", token: "tok-en", platform: "android", locale: "en", timezone: "America/Argentina/Buenos_Aires" },
      { id: "d-dead", token: "tok-dead", platform: "android", locale: "es", timezone: "UTC" },
    ],
  });
  const id = s.add("u1", "weekly_report", { week_start: "2026-10-05" });
  const sender = new FakeSender();
  sender.results.set("tok-dead", "invalid_token");

  const r = await runDispatch(s, sender, () => noonBA);
  assertEquals(r.sent, 1);
  assertEquals(r.invalidTokens, 1);
  assertEquals(s.deletedDevices, ["d-dead"]);
  assertEquals(s.logs[0].device_count, 2);
  assertEquals(s.row(id).status, "sent");
  const titles = sender.sent.map((m) => `${m.token}:${m.title}`).sort();
  assertEquals(titles[0], "tok-dead:Tu semana en Porty está lista");
  assertEquals(titles[1], "tok-en:Your week in Porty is ready");
  for (const m of sender.sent) {
    assertEquals(m.data.route, "weekly_report");
    assertEquals(m.data.log_id, "1");
    assertEquals(m.androidChannel, "reports");
  }
});

Deno.test("despacho: si no llegó a ningún dispositivo vuelve a la cola, y a los 3 intentos falla", async () => {
  const s = new MemoryDispatchStore(() => noonBA);
  s.user("u1");
  const id = s.add("u1", "price_alert", { symbol: "VOO", condition: "below", target: 500, price: 499 });
  const sender = new FakeSender();
  sender.results.set("tok-u1", "retry");
  for (let i = 0; i < 3; i++) await runDispatch(s, sender, () => noonBA);
  assertEquals(s.row(id).status, "failed");
  assertEquals(s.logs.length, 0);
});

// ── plantillas ──────────────────────────────────────────────────────────────

Deno.test("plantillas: sin montos del usuario salvo con show_amounts", () => {
  const data = { change_pct: -3.42, change_value: -1234.5, benchmark_change_pct: -2.1, moves: [{ symbol: "NVDA", change_pct: -7.2 }] };
  const hidden = render("portfolio_move", data, { locale: "es", showAmounts: false });
  assertEquals(hidden.title, "Tu cartera baja 3.4% hoy");
  assertEquals(hidden.body, "El S&P 500 baja 2.1%. Lo que más pesa: NVDA -7.2%.");
  assert(!hidden.title.includes("$"));
  const shown = render("portfolio_move", data, { locale: "en", showAmounts: true });
  assertEquals(shown.title, "Your portfolio is down 3.4% today (-$1,234.50)");
});

Deno.test("plantillas: alertas, movimientos y earnings", () => {
  const above = render("price_alert", { symbol: "VOO", condition: "above", target: 750, price: 751.2, alert_id: "a1" }, { locale: "es", showAmounts: false });
  assertEquals(above.title, "VOO pasó $750.00");
  assertEquals(above.body, "Ahora está en $751.20.");
  assertEquals(above.route, "ticker");
  assertEquals(above.routeArgs, { ticker: "VOO", alert_id: "a1" });

  const pct = render("price_alert", { symbol: "NVDA", condition: "pct_down", target: 10, reference_price: 180, price: 161.5, repeat: "daily" }, { locale: "en", showAmounts: false });
  assertEquals(pct.title, "NVDA is down 10% since your alert");
  assertStringIncludes(pct.body, "(it was $180.00)");
  assertStringIncludes(pct.body, "crosses again");

  const move = render("big_move", { symbol: "NVDA", change_pct: -7.24, weight_pct: 24.4 }, { locale: "es", showAmounts: false });
  assertEquals(move.title, "NVDA baja 7.2% hoy");
  assertMatch(move.body, /^Pesa 24% en tu cartera\./);
  assertEquals(move.route, "assistant");
  assertEquals(move.routeArgs.question, "¿Por qué se mueve NVDA hoy?");

  const digest = render("big_move_digest", { moves: [{ symbol: "NVDA", change_pct: -7.2 }, { symbol: "AMD", change_pct: -6.1 }] }, { locale: "es", showAmounts: false });
  assertEquals(digest.title, "2 de tus acciones se mueven fuerte hoy");
  assertEquals(digest.body, "NVDA -7.2% · AMD -6.1%");

  const tomorrow = render("earnings_tomorrow", { symbols: ["AAPL", "MSFT", "NVDA"] }, { locale: "es", showAmounts: false });
  assertEquals(tomorrow.title, "AAPL, MSFT y NVDA presentan resultados mañana");
  const result = render("earnings_result", { symbol: "AAPL", surprise: "beat", eps_actual: 1.52, eps_estimate: 1.43 }, { locale: "en", showAmounts: false });
  assertEquals(result.body, "Earnings per share came in above expectations ($1.52 vs. $1.43).");
});

Deno.test("plantillas: ningún texto da consejos ni usa tono de casino", () => {
  const banned = /compr[áa]|vend[ée]|\bbuy\b|\bsell\b|oportunidad|opportunit|🚀|!|ahora o nunca|don't miss/i;
  const samples: [Parameters<typeof render>[0], Record<string, unknown>][] = [
    ["test", {}],
    ["price_alert", { symbol: "VOO", condition: "below", target: 500, price: 499 }],
    ["big_move", { symbol: "NVDA", change_pct: 9, weight_pct: 30 }],
    ["big_move_digest", { moves: [{ symbol: "A", change_pct: 5 }] }],
    ["portfolio_move", { change_pct: 3.5 }],
    ["weekly_report", {}],
    ["etoro_reconnect", {}],
    ["earnings_tomorrow", { symbols: ["AAPL"] }],
    ["earnings_result", { symbol: "AAPL", surprise: "miss" }],
  ];
  for (const locale of ["es", "en"] as const) {
    for (const [kind, data] of samples) {
      const r = render(kind, data, { locale, showAmounts: true });
      assert(!banned.test(`${r.title} ${r.body}`), `${kind}/${locale}: ${r.title} ${r.body}`);
      assert(r.title.length <= 65, `${kind}/${locale}: título largo`);
    }
  }
});

// ── FCM ─────────────────────────────────────────────────────────────────────

async function testAccount() {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let s = "";
  for (const b of pkcs8) s += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(s).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----\n`;
  return { account: { project_id: "porty-test", client_email: "push@porty-test.iam.gserviceaccount.com", private_key: pem }, publicKey: pair.publicKey };
}

Deno.test("FCM: firma el JWT, reusa el token OAuth y arma el mensaje v1", async () => {
  const { account, publicKey } = await testAccount();
  const calls: { url: string; body: string }[] = [];
  const fetchImpl = ((url: string, init?: RequestInit) => {
    calls.push({ url, body: String(init?.body ?? "") });
    if (url.includes("oauth2")) return Promise.resolve(Response.json({ access_token: "at-1", expires_in: 3600 }));
    return Promise.resolve(Response.json({ name: "projects/porty-test/messages/1" }));
  }) as typeof fetch;
  const sender = FcmSender.fromEnv(JSON.stringify(account), fetchImpl, () => noonBA)!;
  const msg: FcmMessage = {
    token: "device-token", title: "VOO pasó $750.00", body: "Ahora está en $751.20.",
    data: { kind: "price_alert", route: "ticker", ticker: "VOO" },
    androidChannel: "price_alerts", interruption: "time-sensitive", threadId: "price_alert",
  };
  assertEquals(await sender.send(msg), "ok");
  assertEquals(await sender.send(msg), "ok");
  assertEquals(calls.filter((c) => c.url.includes("oauth2")).length, 1);

  // El JWT verifica con la clave pública.
  const assertion = new URLSearchParams(calls[0].body).get("assertion")!;
  const [h, c, sig] = assertion.split(".");
  const b64 = (x: string) => Uint8Array.from(atob(x.replace(/-/g, "+").replace(/_/g, "/")), (ch) => ch.charCodeAt(0));
  assert(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", publicKey, b64(sig), new TextEncoder().encode(`${h}.${c}`)));
  const claims = JSON.parse(new TextDecoder().decode(b64(c)));
  assertEquals(claims.iss, account.client_email);
  assertEquals(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");

  const sent = JSON.parse(calls[1].body).message;
  assertEquals(calls[1].url, "https://fcm.googleapis.com/v1/projects/porty-test/messages:send");
  assertEquals(sent.token, "device-token");
  assertEquals(sent.android.notification.channel_id, "price_alerts");
  assertEquals(sent.apns.payload.aps["interruption-level"], "time-sensitive");
  assertEquals(sent.data.ticker, "VOO");
});

Deno.test("FCM: 401 renueva el token una vez; errores clasificados", async () => {
  const { account } = await testAccount();
  let sends = 0;
  let oauth = 0;
  const fetchImpl = ((url: string) => {
    if (url.includes("oauth2")) return Promise.resolve(Response.json({ access_token: `at-${++oauth}`, expires_in: 3600 }));
    return Promise.resolve(++sends === 1 ? new Response("", { status: 401 }) : Response.json({}));
  }) as typeof fetch;
  const sender = FcmSender.fromEnv(JSON.stringify(account), fetchImpl, () => noonBA)!;
  assertEquals(await sender.send({ token: "t", title: "a", body: "b", data: {}, androidChannel: "account", interruption: "active", threadId: "x" }), "ok");
  assertEquals(oauth, 2);

  const unregistered = JSON.stringify({ error: { status: "NOT_FOUND", details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: "UNREGISTERED" }] } });
  assertEquals(classify(404, unregistered), "invalid_token");
  assertEquals(classify(400, JSON.stringify({ error: { status: "INVALID_ARGUMENT", message: "The registration token is not a valid FCM registration token" } })), "invalid_token");
  assertEquals(classify(429, "{}"), "retry");
  assertEquals(classify(503, ""), "retry");
  assertEquals(classify(400, JSON.stringify({ error: { status: "INVALID_ARGUMENT", message: "Invalid JSON payload" } })), "error");
  assertEquals(FcmSender.fromEnv("no es json", fetchImpl, () => 0), null);
});

// ── handler ─────────────────────────────────────────────────────────────────

Deno.test("handler: solo con el secreto del cron", async () => {
  const s = new MemoryDispatchStore(() => noonBA);
  const deps = { env: (k: string) => (k === "CRON_SECRET" ? "s3cret" : undefined), now: () => noonBA, store: s, sender: new FakeSender() };
  const req = (secret?: string) =>
    new Request("http://local/functions/v1/notify-dispatch", { method: "POST", headers: secret ? { "x-cron-secret": secret } : {} });
  assertEquals((await handle(req(), deps)).status, 401);
  assertEquals((await handle(req("otro-secret"), deps)).status, 401);
  assertEquals((await handle(req("s3cret"), deps)).status, 200);
  assertEquals((await handle(req("s3cret"), { ...deps, sender: null })).status, 503);
  // Sin CRON_SECRET configurado nadie entra.
  assertEquals((await handle(req("s3cret"), { ...deps, env: () => undefined })).status, 401);
});

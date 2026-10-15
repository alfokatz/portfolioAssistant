// Uso: ver docs/runbooks/ai-proxy-cutover.md → "Medir latencia".
// Proxy overhead probe: same body, direct to OpenAI vs through local ai-chat.
// With an invalid key OpenAI answers 401 after a full network round trip, so
// (proxy - direct) = gateway + edge runtime + JWT check + ai_begin_request.
const API = Deno.env.get("API_URL")!;
const SERVICE = Deno.env.get("SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("ANON_KEY")!;
const N = Number(Deno.env.get("N") ?? 20);
// PROMPT_FILE: el system prompt real (ver runbook), así el body pesa lo
// mismo que en la app y pasa la allowlist.
const prompt = await Deno.readTextFile(Deno.env.get("PROMPT_FILE") ?? "system_prompt.txt");

const email = `latency-${crypto.randomUUID()}@example.test`;
const password = crypto.randomUUID();
const created = await fetch(`${API}/auth/v1/admin/users`, {
  method: "POST",
  headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" },
  body: JSON.stringify({ email, password, email_confirm: true }),
});
if (!created.ok) throw new Error(`create user ${created.status}`);
const login = await (await fetch(`${API}/auth/v1/token?grant_type=password`, {
  method: "POST",
  headers: { apikey: ANON, "Content-Type": "application/json" },
  body: JSON.stringify({ email, password }),
})).json();
const jwt = login.access_token as string;

const body = JSON.stringify({
  model: "gpt-4.1-mini",
  messages: [
    { role: "system", content: [{ type: "text", text: prompt }] },
    { role: "system", content: "PORTFOLIO_BRIEF — cartera: {}" },
    { role: "user", content: "hola" },
  ],
});
console.log(`body ${(body.length / 1024).toFixed(0)} KB, N=${N}`);

async function time(url: string, headers: Record<string, string>) {
  const t = performance.now();
  const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body });
  const text = await r.text();
  return { ms: performance.now() - t, status: r.status, text };
}
const pct = (xs: number[], p: number) => [...xs].sort((a, b) => a - b)[Math.min(xs.length - 1, Math.floor(p * xs.length))];

const direct: number[] = [], proxy: number[] = [];
// warm-up (worker boot, TLS) — not counted
await time("https://api.openai.com/v1/chat/completions", { Authorization: "Bearer sk-invalid" });
const w = await time(`${API}/functions/v1/ai-chat`, { Authorization: `Bearer ${jwt}`, apikey: ANON, "x-porty-turn-id": `warm-${crypto.randomUUID()}` });
console.log("warm-up proxy status", w.status, w.text.slice(0, 120));
for (let i = 0; i < N; i++) {
  const d = await time("https://api.openai.com/v1/chat/completions", { Authorization: "Bearer sk-invalid" });
  direct.push(d.ms);
  const p = await time(`${API}/functions/v1/ai-chat`, { Authorization: `Bearer ${jwt}`, apikey: ANON, "x-porty-turn-id": `lat-${crypto.randomUUID()}` });
  if (p.status !== 401) console.log("unexpected proxy status", p.status, p.text.slice(0, 200));
  proxy.push(p.ms);
}
const fmt = (xs: number[]) => `p50 ${pct(xs, .5).toFixed(0)} ms · p90 ${pct(xs, .9).toFixed(0)} ms · max ${Math.max(...xs).toFixed(0)} ms`;
console.log("direct →", fmt(direct));
console.log("proxy  →", fmt(proxy));
const diffs = proxy.map((p, i) => p - direct[i]);
console.log("overhead (paired) →", fmt(diffs));

// Proxy-only cost: a disallowed model is rejected by ai_begin_request, i.e.
// right before the upstream call (after gateway, JWT, parse, hash, RPC).
const localOnly: number[] = [];
const bad = JSON.parse(body); bad.model = "gpt-4.1";
const badBody = JSON.stringify(bad);
for (let i = 0; i < N; i++) {
  const t = performance.now();
  const r = await fetch(`${API}/functions/v1/ai-chat`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${jwt}`, apikey: ANON, "x-porty-turn-id": `loc-${crypto.randomUUID()}` }, body: badBody });
  await r.text();
  if (r.status !== 400) console.log("unexpected", r.status);
  localOnly.push(performance.now() - t);
}
console.log("proxy own work (pre-upstream) →", fmt(localOnly));

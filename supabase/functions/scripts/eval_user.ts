// Crea un usuario de prueba con plan Gold en el proyecto de API_URL y
// imprime su JWT (para EVAL_PROXY_JWT). Solo local / proyecto de desarrollo.
//
//   eval "$(supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY|ANON_KEY)=' | sed 's/^/export /')"
//   export EVAL_PROXY_JWT=$(deno run -A scripts/eval_user.ts)
const API = Deno.env.get("API_URL")!;
const SERVICE = Deno.env.get("SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("ANON_KEY")!;
if (!API || !SERVICE || !ANON) throw new Error("API_URL, SERVICE_ROLE_KEY y ANON_KEY son obligatorios");
if (!/127\.0\.0\.1|localhost/.test(API) && Deno.env.get("ALLOW_REMOTE") !== "1") {
  throw new Error("API_URL no es local: exportá ALLOW_REMOTE=1 si es el proyecto de DESARROLLO");
}

const email = `eval-${crypto.randomUUID()}@example.test`;
const password = crypto.randomUUID();
const admin = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" };
const created = await fetch(`${API}/auth/v1/admin/users`, {
  method: "POST",
  headers: admin,
  body: JSON.stringify({ email, password, email_confirm: true }),
});
if (!created.ok) throw new Error(`create user: ${created.status} ${await created.text()}`);
const { id } = await created.json();

// Gold: 1000/mes y 100/día (plan_limits) — alcanza para una corrida completa
// de evals; una segunda corrida el mismo día conviene hacerla con otro usuario.
const up = await fetch(`${API}/rest/v1/rpc/upsert_subscription_from_provider`, {
  method: "POST",
  headers: admin,
  body: JSON.stringify({
    p_user_id: id,
    p_tier: "gold",
    p_provider: "eval",
    p_external_subscription_id: "eval",
    p_status: "active",
    p_current_period_end: new Date(Date.now() + 7 * 864e5).toISOString(),
  }),
});
if (!up.ok) throw new Error(`upsert subscription: ${up.status} ${await up.text()}`);

const login = await fetch(`${API}/auth/v1/token?grant_type=password`, {
  method: "POST",
  headers: { apikey: ANON, "Content-Type": "application/json" },
  body: JSON.stringify({ email, password }),
});
if (!login.ok) throw new Error(`login: ${login.status}`);
console.log((await login.json()).access_token);

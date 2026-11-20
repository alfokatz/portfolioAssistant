// Crea N usuarios de prueba (plan premium por defecto, para que el brief sea
// `full`) con una posición cargada, el interruptor `daily_brief` prendido para
// ellos y el brief de un día hábil válido ya reservado (claim_daily_brief →
// claimed). Imprime [{jwt, day}] para los evals del brief diario. Un usuario
// por caso: el proxy topea las rondas del LLM por claim (2). Solo local /
// proyecto de desarrollo.
//
//   eval "$(supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY|ANON_KEY)=' | sed 's/^/export /')"
//   deno run -A scripts/eval_brief_users.ts [N=20] [plan=premium] > /tmp/brief_users.json
//
// Los usuarios se AGREGAN a app_config.daily_brief.users sin pisar los que ya
// están. Limpieza: docs/runbooks/daily-brief.md → Evals.
import { createClient } from "npm:@supabase/supabase-js@2";

const API = Deno.env.get("API_URL")!;
const SERVICE = Deno.env.get("SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("ANON_KEY")!;
if (!API || !SERVICE || !ANON) throw new Error("API_URL, SERVICE_ROLE_KEY y ANON_KEY son obligatorios");
if (!/127\.0\.0\.1|localhost/.test(API) && Deno.env.get("ALLOW_REMOTE") !== "1") {
  throw new Error("API_URL no es local: exportá ALLOW_REMOTE=1 si es el proyecto de DESARROLLO");
}

const count = Number(Deno.args[0] ?? "20");
const plan = Deno.args[1] ?? "premium";
if (!Number.isInteger(count) || count < 1 || count > 200) throw new Error("N tiene que ser un entero entre 1 y 200");
if (!["free", "premium", "gold"].includes(plan)) throw new Error("plan: free | premium | gold");
const admin = createClient(API, SERVICE, { auth: { persistSession: false } });

/// Día hábil dentro de _daily_brief_valid_day (ayer..mañana en UTC, lun-vie):
/// hoy si es hábil, si no ayer, si no mañana.
function validDay(): string {
  const base = Date.now();
  for (const offset of [0, -1, 1]) {
    const d = new Date(base + offset * 86_400_000);
    const dow = d.getUTCDay(); // 0 = domingo
    if (dow >= 1 && dow <= 5) return d.toISOString().slice(0, 10);
  }
  throw new Error("sin día hábil válido"); // inalcanzable
}
const day = validDay();

// 1) Usuarios con plan y una posición.
const ids: string[] = [];
const creds: { email: string; password: string }[] = [];
for (let i = 0; i < count; i++) {
  const email = `eval-brief-${crypto.randomUUID()}@example.test`;
  const password = `Ev-${crypto.randomUUID()}`; // minúsculas, MAYÚSCULAS y dígitos (config.toml)
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (created.error) throw created.error;
  const id = created.data.user!.id;
  if (plan !== "free") {
    const up = await admin.rpc("upsert_subscription_from_provider", {
      p_user_id: id,
      p_tier: plan,
      p_provider: "eval",
      p_external_subscription_id: "eval",
      p_status: "active",
      p_current_period_end: new Date(Date.now() + 7 * 864e5).toISOString(),
    });
    if (up.error) throw up.error;
  }
  const pos = await admin.from("positions").insert({
    id: crypto.randomUUID(),
    user_id: id,
    ticker: "AAPL",
    quantity: 1,
    purchase_price: 100,
    purchase_date: new Date().toISOString(),
  });
  if (pos.error) throw pos.error;
  ids.push(id);
  creds.push({ email, password });
}

// 2) Interruptor: se suman a `users` (sin duplicar ni pisar los existentes).
const cfg = await admin.from("app_config").select("value").eq("key", "daily_brief").single();
if (cfg.error) throw cfg.error;
const value = (cfg.data.value ?? {}) as Record<string, unknown>;
const current = Array.isArray(value.users) ? (value.users as string[]) : [];
const users = [...new Set([...current, ...ids])];
const upd = await admin
  .from("app_config")
  .update({ value: { ...value, users }, updated_at: new Date().toISOString() })
  .eq("key", "daily_brief");
if (upd.error) throw upd.error;

// 3) JWT y claim del día.
const out: { jwt: string; day: string }[] = [];
for (const { email, password } of creds) {
  const anon = createClient(API, ANON, { auth: { persistSession: false } });
  const signed = await anon.auth.signInWithPassword({ email, password });
  if (signed.error) throw signed.error;
  const jwt = signed.data.session!.access_token;
  const user = createClient(API, ANON, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const claim = await user.rpc("claim_daily_brief", { p_day: day });
  if (claim.error || claim.data?.state !== "claimed") {
    throw new Error(`claim: ${claim.error?.message ?? JSON.stringify(claim.data)}`);
  }
  if (claim.data.variant !== "full") throw new Error(`claim sin variante full: ${JSON.stringify(claim.data)}`);
  out.push({ jwt, day });
}
console.log(JSON.stringify(out));

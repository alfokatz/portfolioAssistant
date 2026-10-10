// Crea N usuarios Gold de prueba con el informe de la última semana cerrada
// ya reservado (claim_weekly_report) e imprime [{jwt, week}] para los evals
// del informe semanal. Un usuario por caso: el proxy topea las llamadas al
// LLM por usuario y semana. Solo local / proyecto de desarrollo.
//
//   eval "$(supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY|ANON_KEY)=' | sed 's/^/export /')"
//   deno run -A scripts/eval_report_users.ts 12 > /tmp/report_users.json
//
// El informe arranca apagado (app_config.weekly_report): en la base local hay
// que prenderlo antes (ver docs/runbooks/weekly-report.md → Evals).
import { createClient } from "npm:@supabase/supabase-js@2";

const API = Deno.env.get("API_URL")!;
const SERVICE = Deno.env.get("SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("ANON_KEY")!;
if (!API || !SERVICE || !ANON) throw new Error("API_URL, SERVICE_ROLE_KEY y ANON_KEY son obligatorios");
if (!/127\.0\.0\.1|localhost/.test(API) && Deno.env.get("ALLOW_REMOTE") !== "1") {
  throw new Error("API_URL no es local: exportá ALLOW_REMOTE=1 si es el proyecto de DESARROLLO");
}

const count = Number(Deno.args[0] ?? "12");
const admin = createClient(API, SERVICE, { auth: { persistSession: false } });

/// Lunes de la semana cerrada anterior (dentro de _valid_report_week).
const d = new Date(Date.now() - 7 * 86_400_000);
d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() || 7) - 1));
const week = d.toISOString().slice(0, 10);

const out: { jwt: string; week: string }[] = [];
for (let i = 0; i < count; i++) {
  const email = `eval-report-${crypto.randomUUID()}@example.test`;
  const password = crypto.randomUUID();
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (created.error) throw created.error;
  const up = await admin.rpc("upsert_subscription_from_provider", {
    p_user_id: created.data.user!.id,
    p_tier: "gold",
    p_provider: "eval",
    p_external_subscription_id: "eval",
    p_status: "active",
    p_current_period_end: new Date(Date.now() + 7 * 864e5).toISOString(),
  });
  if (up.error) throw up.error;
  const anon = createClient(API, ANON, { auth: { persistSession: false } });
  const signed = await anon.auth.signInWithPassword({ email, password });
  if (signed.error) throw signed.error;
  const jwt = signed.data.session!.access_token;
  const user = createClient(API, ANON, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const claim = await user.rpc("claim_weekly_report", { p_week_start: week });
  if (claim.data?.state === "disabled") {
    throw new Error("El informe está apagado: prendé app_config.weekly_report en la base local");
  }
  if (claim.error || claim.data?.state !== "claimed") {
    throw new Error(`claim: ${claim.error?.message ?? JSON.stringify(claim.data)}`);
  }
  out.push({ jwt, week });
}
console.log(JSON.stringify(out));

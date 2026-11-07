// Landing de validación de Porty (repo porty-web). Pública, sin JWT: la
// llama la Pages Function de porty-web (`/api/*`), que agrega el país y la
// IP del visitante en headers firmados con LANDING_PROXY_SECRET.
//
//   POST /landing/signup {email, consent, variant, intended_plan?, utm?,
//                         referred_by?, anon_id?, path?, website}
//     → 200 {position, ref_code}
//   POST /landing/event  {anon_id, event, variant?, plan?, path?, utm?}
//     → 204
//
// - `website` es el honeypot: si viene con algo, respondemos como si nada y
//   no guardamos.
// - Rate limit por IP con un hash con sal (`landing_rate_hit`): la IP no se
//   guarda nunca.
// - `signup` y `founder_signup` los registra `landing_signup` en la base; el
//   cliente no los puede mandar.

import { corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";

export const config = {
  signupPerMinute: 5,
  eventPerMinute: 60,
  maxUtmLength: 100,
};

const variants = new Set(["a", "b", "c"]);
const plans = new Set(["free", "premium", "gold"]);
const clientEvents = new Set([
  "page_view",
  "form_view",
  "pricing_view",
  "plan_click",
  "founder_modal_open",
]);
const utmKeys = ["utm_source", "utm_medium", "utm_campaign", "utm_content"] as const;

// Suficiente para descartar lo que no es un email; el resto lo resuelve el
// email de confirmación de la beta.
const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export function isEmail(value: unknown): value is string {
  return typeof value === "string" && value.trim().length <= 254 && emailRe.test(value.trim());
}

type Utm = Partial<Record<(typeof utmKeys)[number], string>>;

export function cleanUtm(raw: unknown): Utm {
  const out: Utm = {};
  if (!raw || typeof raw !== "object") return out;
  for (const k of utmKeys) {
    const v = (raw as Record<string, unknown>)[k];
    if (typeof v === "string" && v.trim()) out[k] = v.trim().slice(0, config.maxUtmLength);
  }
  return out;
}

function cleanAnonId(raw: unknown): string | null {
  return typeof raw === "string" && /^[A-Za-z0-9-]{8,64}$/.test(raw) ? raw : null;
}

function cleanPath(raw: unknown): string | null {
  return typeof raw === "string" && raw.startsWith("/") ? raw.slice(0, 200) : null;
}

/// IP y país del visitante. Solo se confía en los headers del proxy si
/// traen el secreto; si no (llamada directa), IP del gateway y sin país.
export function visitor(req: Request, deps: Deps): { ip: string; country: string | null } {
  const secret = deps.env("LANDING_PROXY_SECRET");
  if (secret && req.headers.get("x-landing-proxy-secret") === secret) {
    const country = (req.headers.get("x-landing-country") ?? "").toUpperCase();
    return {
      ip: req.headers.get("x-landing-ip") ?? "unknown",
      // Cloudflare usa XX (desconocido) y T1 (Tor).
      country: /^[A-Z]{2}$/.test(country) && country !== "XX" && country !== "T1" ? country : null,
    };
  }
  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return { ip: forwarded || "unknown", country: null };
}

/// Hash de la IP con sal y fecha: alcanza para contar pedidos por minuto
/// sin poder volver a la IP.
export async function ipHash(ip: string, deps: Deps): Promise<string> {
  const day = new Date(deps.now()).toISOString().slice(0, 10);
  const data = new TextEncoder().encode(`${deps.env("LANDING_IP_SALT") ?? ""}:${day}:${ip}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function allowed(req: Request, deps: Deps, bucket: string, perMinute: number) {
  const { ip } = visitor(req, deps);
  const rate = await deps.db.rpc("landing_rate_hit", {
    p_key_hash: await ipHash(ip, deps),
    p_bucket: bucket,
    p_per_minute: perMinute,
  });
  // Si la base falla, mejor dejar pasar que perder un registro.
  return rate.data !== false;
}

async function signup(req: Request, body: Record<string, unknown>, deps: Deps) {
  // Honeypot: un bot completa todos los campos. Le respondemos igual.
  if (typeof body.website === "string" && body.website !== "") {
    return json(200, { position: null, ref_code: null });
  }
  if (!isEmail(body.email)) return typedError(400, "invalid_email", "Email inválido");
  if (body.consent !== true) return typedError(400, "consent_required", "Falta el consentimiento");
  const variant = typeof body.variant === "string" && variants.has(body.variant) ? body.variant : null;
  if (!variant) return typedError(400, "invalid_variant", "variant debe ser a, b o c");
  let plan: string | null = null;
  if (body.intended_plan != null) {
    if (typeof body.intended_plan !== "string" || !plans.has(body.intended_plan)) {
      return typedError(400, "invalid_plan", "intended_plan debe ser free, premium o gold");
    }
    plan = body.intended_plan;
  }

  if (!(await allowed(req, deps, "signup", config.signupPerMinute))) {
    return typedError(429, "rate_limited", "Demasiados intentos");
  }

  const referredBy = typeof body.referred_by === "string" && /^[A-Za-z2-9]{6}$/.test(body.referred_by)
    ? body.referred_by.toUpperCase()
    : null;

  const { data, error } = await deps.db.rpc("landing_signup", {
    p_email: body.email,
    p_variant: variant,
    p_intended_plan: plan,
    p_utm: cleanUtm(body.utm),
    p_referred_by: referredBy,
    p_country: visitor(req, deps).country,
    p_anon_id: cleanAnonId(body.anon_id),
    p_path: cleanPath(body.path),
  });
  if (error || !data) {
    console.error("landing_signup failed", error);
    return typedError(500, "signup_failed", "No pudimos registrarte");
  }
  return json(200, { position: data.position, ref_code: data.ref_code });
}

async function event(req: Request, body: Record<string, unknown>, deps: Deps) {
  const anonId = cleanAnonId(body.anon_id);
  if (!anonId) return typedError(400, "invalid_anon_id", "anon_id inválido");
  if (typeof body.event !== "string" || !clientEvents.has(body.event)) {
    return typedError(400, "invalid_event", "Evento desconocido");
  }
  if (!(await allowed(req, deps, "event", config.eventPerMinute))) {
    return typedError(429, "rate_limited", "Demasiados eventos");
  }
  const variant = typeof body.variant === "string" && variants.has(body.variant) ? body.variant : null;
  const plan = typeof body.plan === "string" && plans.has(body.plan) ? body.plan : null;
  const { error } = await deps.db.from("landing_events").insert({
    anon_id: anonId,
    variant,
    event: body.event,
    plan,
    path: cleanPath(body.path),
    ...cleanUtm(body.utm),
  });
  if (error) {
    console.error("landing_events insert failed", error);
    return typedError(500, "event_failed", "No pudimos registrar el evento");
  }
  return new Response(null, { status: 204, headers: corsHeaders });
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");

  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    body = parsed;
  } catch {
    return typedError(400, "invalid_body", "JSON object expected");
  }

  const route = new URL(req.url).pathname.replace(/\/+$/, "").split("/").pop();
  if (route === "signup") return signup(req, body, deps);
  if (route === "event") return event(req, body, deps);
  return typedError(404, "not_found", "Use /signup or /event");
}

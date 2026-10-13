// Landing de validación (repo porty-web): lista de espera y eventos.
// Deploy: supabase functions deploy landing --no-verify-jwt
// Secrets: LANDING_PROXY_SECRET (el mismo que la Pages Function de
// porty-web manda en `x-landing-proxy-secret`), LANDING_IP_SALT (cualquier
// string largo y aleatorio).
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

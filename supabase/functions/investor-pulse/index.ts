// Deploy: supabase functions deploy investor-pulse
// Secrets: SEC_USER_AGENT ("Porty <contacto@dominio>": la SEC exige
// identificarse). Sin él, solo noticias.
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

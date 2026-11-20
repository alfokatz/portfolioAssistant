// Deploy: supabase functions deploy sec
// Secrets: SEC_USER_AGENT ("Porty <contacto@dominio>", el mismo de
// investor-pulse: la SEC exige identificarse).
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

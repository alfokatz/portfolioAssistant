// Deploy: supabase functions deploy headlines
// Secrets: SEC_USER_AGENT (nombre de la empresa desde el mapa de la SEC;
// GDELT es público). La app la llama con su JWT; GDELT nunca desde la app.
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

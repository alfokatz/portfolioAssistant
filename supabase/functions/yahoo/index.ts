// Deploy: supabase functions deploy yahoo
// Sin secrets: Yahoo no usa key (la sesión se arma en el handler).
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

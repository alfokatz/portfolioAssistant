// Deploy: supabase functions deploy ai-chat
// Secrets: OPENAI_API_KEY (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY los pone la plataforma).
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

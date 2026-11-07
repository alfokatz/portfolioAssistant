// Deploy: supabase functions deploy news-context
// Secrets: OPENAI_API_KEY (el mismo de ai-chat), SEC_USER_AGENT (nombre de
// la empresa desde el mapa de la SEC); opcional NEWS_CONTEXT_MODEL.
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

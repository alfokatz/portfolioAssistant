// Deploy: supabase functions deploy web-search
// Secrets: OPENAI_API_KEY (el mismo de ai-chat); opcional WEB_SEARCH_MODEL.
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

// Deploy: supabase functions deploy statement-import
// Secrets: OPENAI_API_KEY (ya existe) y, opcional, STATEMENT_IMPORT_MODEL
// (default gpt-6-luna; tiene que estar habilitado en `model_prices`).
import { defaultDeps } from "../_shared/common.ts";
import { handle, supabaseQuota } from "./handler.ts";

const deps = defaultDeps();
const quota = supabaseQuota(deps.db);
Deno.serve((req) => handle(req, { ...deps, quota }));

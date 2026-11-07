// Deploy: supabase functions deploy finnhub
// Secrets: FINNHUB_API_KEY.
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

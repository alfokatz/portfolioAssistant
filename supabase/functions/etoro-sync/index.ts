// Deploy: supabase functions deploy etoro-sync --no-verify-jwt
// (el callback de eToro llega sin JWT; las demás rutas lo validan ellas).
// Secrets: ETORO_CLIENT_ID, ETORO_CLIENT_SECRET, ETORO_REDIRECT_URI y,
// opcional, ETORO_APP_REDIRECT (default porty-etoro://callback).
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

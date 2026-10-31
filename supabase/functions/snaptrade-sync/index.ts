// Deploy: supabase functions deploy snaptrade-sync
// Secrets: SNAPTRADE_CLIENT_ID y SNAPTRADE_CONSUMER_KEY (sin ellos responde
// 503 snaptrade_not_configured). Opcionales: SNAPTRADE_APP_REDIRECT (default
// porty-snaptrade://callback), SNAPTRADE_MANUAL_REFRESH=on y
// SNAPTRADE_REFRESH_PER_DAY (ver docs/runbooks/snaptrade-sync.md).
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

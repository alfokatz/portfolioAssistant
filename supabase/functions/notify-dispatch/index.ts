// Deploy: supabase functions deploy notify-dispatch
// Secrets: CRON_SECRET, FCM_SERVICE_ACCOUNT (JSON de la service account).
import { defaultDeps } from "../_shared/common.ts";
import { FcmSender } from "./fcm.ts";
import { handle } from "./handler.ts";
import { supabaseDispatchStore } from "./store.ts";

const deps = defaultDeps();
const sender = FcmSender.fromEnv(deps.env("FCM_SERVICE_ACCOUNT"), deps.fetch, deps.now);
Deno.serve((req) =>
  handle(req, { env: deps.env, now: deps.now, store: supabaseDispatchStore(deps.db), sender })
);

// Deploy: supabase functions deploy daily-jobs
// Secrets: CRON_SECRET, FCM_SERVICE_ACCOUNT, FINNHUB_API_KEY (calendario de
// earnings). La agenda (pg_cron) está en docs/runbooks/push-notifications.md.
import { defaultDeps } from "../_shared/common.ts";
import { FcmSender } from "../notify-dispatch/fcm.ts";
import { supabaseDispatchStore } from "../notify-dispatch/store.ts";
import { handle } from "./handler.ts";
import { supabaseJobsStore } from "./store.ts";

const deps = defaultDeps();
const sender = FcmSender.fromEnv(deps.env("FCM_SERVICE_ACCOUNT"), deps.fetch, deps.now);
Deno.serve((req) =>
  handle(req, {
    env: deps.env,
    now: deps.now,
    fetch: deps.fetch,
    store: supabaseJobsStore(deps.db),
    dispatchStore: supabaseDispatchStore(deps.db),
    sender,
  })
);

// RevenueCat webhook → user_subscriptions (vía service role).
// Deploy: supabase functions deploy revenuecat-webhook --no-verify-jwt
// Secrets: REVENUECAT_WEBHOOK_SECRET (el mismo "Authorization header" que se
// configura en RevenueCat, sin "Bearer "), REVENUECAT_SECRET_API_KEY (sk_…).
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

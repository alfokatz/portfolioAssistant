// Deploy: supabase functions deploy news-warm --no-verify-jwt
// La llama pg_cron (cada 15 min, solo con el interruptor `daily_brief`
// prendido) con `x-cron-secret`: sin JWT.
// Secrets: CRON_SECRET, OPENAI_API_KEY (digests), SEC_USER_AGENT (nombre de la
// empresa para titulares), YOUTUBE_API_KEY (videos; sin ella, la pieza de
// videos queda vacía), opcional NEWS_CONTEXT_MODEL.
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));

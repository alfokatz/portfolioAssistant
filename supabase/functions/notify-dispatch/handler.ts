// notify-dispatch: manda lo pendiente de `notification_outbox`. La llama
// pg_cron cada minuto (lo diferido por el silencio, lo que escribió
// etoro-sync) y market-watch / daily-jobs apenas escriben algo.
//
// POST /functions/v1/notify-dispatch con `x-cron-secret`.

import { corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { isCronRequest } from "../_shared/cron.ts";
import { runDispatch } from "./dispatch.ts";
import type { PushSender } from "./fcm.ts";
import type { DispatchStore } from "./store.ts";

export type DispatchDeps = Pick<Deps, "env" | "now"> & {
  store: DispatchStore;
  /// null: falta FCM_SERVICE_ACCOUNT.
  sender: PushSender | null;
};

export async function handle(req: Request, deps: DispatchDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");
  if (!isCronRequest(req, deps)) return typedError(401, "unauthorized", "Missing or invalid cron secret");
  if (!deps.sender) return typedError(503, "unavailable", "FCM_SERVICE_ACCOUNT not configured");

  const summary = await runDispatch(deps.store, deps.sender, deps.now);
  console.log(JSON.stringify({ fn: "notify-dispatch", ...summary }));
  return json(200, summary);
}

// daily-jobs: cada hora en punto (pg_cron). Encola lo que corresponde a la
// hora local de cada usuario y lo despacha:
// - sábado 9:00 → "Tu semana en Porty está lista" (F3);
// - 19:00 → earnings de mañana de su cartera (Gold, F6);
// - 12:00 y 19:00 → resultados que ya salieron (Gold, F6);
// - 04:00 UTC → limpieza (push_purge).
//
// POST /functions/v1/daily-jobs con `x-cron-secret`. Body opcional
// `{"hours": [9]}` para correr una hora puntual al probar.

import { corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { isCronRequest } from "../_shared/cron.ts";
import { runDispatch } from "../notify-dispatch/dispatch.ts";
import type { PushSender } from "../notify-dispatch/fcm.ts";
import type { DispatchStore } from "../notify-dispatch/store.ts";
import {
  addDays,
  type EarningsEntry,
  earningsResultRows,
  earningsTomorrowRows,
  jobHours,
  type LocalUser,
  type OutboxInsert,
  parseFinnhubCalendar,
  weeklyReportRows,
} from "./jobs.ts";
import type { JobsStore } from "./store.ts";

export type JobsDeps = Pick<Deps, "env" | "now" | "fetch"> & {
  store: JobsStore;
  dispatchStore: DispatchStore;
  sender: PushSender | null;
};

export type JobsSummary = {
  hours: number[];
  queued: Record<string, number>;
  dispatched: number;
  purged: boolean;
};

export async function handle(req: Request, deps: JobsDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");
  if (!isCronRequest(req, deps)) return typedError(401, "unauthorized", "Missing or invalid cron secret");

  let hours: number[] | undefined;
  try {
    const body = await req.json();
    if (Array.isArray(body?.hours)) hours = body.hours.filter((h: unknown) => Number.isInteger(h));
  } catch {
    // sin body
  }
  const summary = await runDailyJobs(deps, hours);
  console.log(JSON.stringify({ fn: "daily-jobs", ...summary }));
  return json(200, summary);
}

async function fetchCalendar(deps: JobsDeps, from: string, to: string): Promise<EarningsEntry[]> {
  const token = deps.env("FINNHUB_API_KEY");
  if (!token) return [];
  const url = new URL("https://finnhub.io/api/v1/calendar/earnings");
  url.searchParams.set("from", from);
  url.searchParams.set("to", to);
  url.searchParams.set("token", token);
  try {
    const res = await deps.fetch(url.toString());
    if (res.status !== 200) {
      await res.body?.cancel();
      return [];
    }
    return parseFinnhubCalendar(await res.json());
  } catch {
    return [];
  }
}

export async function runDailyJobs(deps: JobsDeps, onlyHours?: number[]): Promise<JobsSummary> {
  const now = deps.now();
  const wanted = new Set(onlyHours ?? [jobHours.weeklyReport, jobHours.earningsTomorrow, ...jobHours.earningsResult]);
  const summary: JobsSummary = { hours: [...wanted].sort((a, b) => a - b), queued: {}, dispatched: 0, purged: false };
  const rows: OutboxInsert[] = [];

  const usersAt = new Map<number, LocalUser[]>();
  for (const h of wanted) usersAt.set(h, await deps.store.usersAtLocalHour(h));

  if (wanted.has(jobHours.weeklyReport)) {
    rows.push(...weeklyReportRows(usersAt.get(jobHours.weeklyReport) ?? [], await deps.store.weeklyReportEnabled()));
  }

  const earningsUsers = [jobHours.earningsTomorrow, ...jobHours.earningsResult]
    .flatMap((h) => (wanted.has(h) ? usersAt.get(h) ?? [] : []))
    .filter((u) => u.tier === "gold" && u.symbols.length > 0);
  if (earningsUsers.length > 0) {
    const today = new Date(now).toISOString().slice(0, 10);
    const calendar = await fetchCalendar(deps, addDays(today, -2), addDays(today, 2));
    if (wanted.has(jobHours.earningsTomorrow)) {
      rows.push(...earningsTomorrowRows(usersAt.get(jobHours.earningsTomorrow) ?? [], calendar));
    }
    for (const h of jobHours.earningsResult) {
      if (wanted.has(h)) rows.push(...earningsResultRows(usersAt.get(h) ?? [], calendar));
    }
  }

  for (const r of rows) summary.queued[r.kind] = (summary.queued[r.kind] ?? 0) + 1;
  const inserted = rows.length > 0 ? await deps.store.enqueue(rows) : 0;

  if (onlyHours === undefined && new Date(now).getUTCHours() === 4) {
    await deps.store.purge();
    summary.purged = true;
  }

  if (inserted > 0 && deps.sender) {
    summary.dispatched = (await runDispatch(deps.dispatchStore, deps.sender, deps.now)).sent;
  }
  return summary;
}

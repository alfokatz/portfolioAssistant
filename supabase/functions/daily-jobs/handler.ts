// daily-jobs: cada hora en punto (pg_cron). Encola lo que corresponde a la
// hora local de cada usuario y lo despacha:
// - sábado 9:00 → "Tu semana en Porty está lista" (F3);
// - 19:00 → earnings de mañana de su cartera (Gold, F6) — solo con
//   `news_provider = legacy` (Finnhub): con v2 (SEC) no hay calendario
//   confirmado y una fecha estimada no alcanza para avisar;
// - 12:00 y 19:00 → resultados que ya salieron (Gold, F6): legacy, por el
//   calendario de Finnhub; v2, por el 8-K con ítem 2.02 presentado a la SEC;
// - lunes 10:00 → la cartera se alejó del plan del usuario (Premium,
//   F3 de docs/superpowers/plans/2026-10-16-porty-siguiente-nivel.md);
// - todos los días 8:00 → lo que Porty marca en la cartera, si hay algo
//   nuevo (docs/superpowers/plans/2026-10-24-porty-en-toda-la-app.md);
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
  allocationDriftRows,
  type EarningsEntry,
  earningsResultRows,
  earningsTomorrowRows,
  jobHours,
  type LocalUser,
  morningBriefRows,
  type OutboxInsert,
  parseFinnhubCalendar,
  weeklyReportRows,
} from "./jobs.ts";
import type { JobsStore } from "./store.ts";

export type JobsDeps = Pick<Deps, "env" | "now" | "fetch"> & {
  store: JobsStore;
  /// v2: comunicados de resultados (8-K 2.02) presentados desde [since] por
  /// [symbols] (ver `secEarningsReleases`).
  secReleases?: (symbols: string[], since: string) => Promise<EarningsEntry[]>;
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
  const wanted = new Set(
    onlyHours ??
      [
        jobHours.morningBrief,
        jobHours.weeklyReport,
        jobHours.allocationDrift,
        jobHours.earningsTomorrow,
        ...jobHours.earningsResult,
      ],
  );
  const summary: JobsSummary = { hours: [...wanted].sort((a, b) => a - b), queued: {}, dispatched: 0, purged: false };
  const rows: OutboxInsert[] = [];

  const usersAt = new Map<number, LocalUser[]>();
  for (const h of wanted) usersAt.set(h, await deps.store.usersAtLocalHour(h));

  if (wanted.has(jobHours.weeklyReport)) {
    rows.push(...weeklyReportRows(usersAt.get(jobHours.weeklyReport) ?? [], await deps.store.weeklyReportEnabled()));
  }

  if (wanted.has(jobHours.allocationDrift) && deps.store.allocationInputs) {
    const mondays = (usersAt.get(jobHours.allocationDrift) ?? []).filter((u) =>
      u.local_dow === 1 && u.symbols.length > 0 && u.tier !== "free"
    );
    if (mondays.length > 0) {
      const inputs = await deps.store.allocationInputs(mondays.map((u) => u.user_id));
      rows.push(...allocationDriftRows(mondays, inputs));
    }
  }

  if (wanted.has(jobHours.morningBrief)) {
    // Con una sola acción no hay concentración ni plan que comparar.
    const morning = (usersAt.get(jobHours.morningBrief) ?? []).filter((u) => u.symbols.length >= 2);
    if (morning.length > 0) {
      const ids = morning.map((u) => u.user_id);
      const paid = morning.filter((u) => u.tier !== "free" && u.local_dow !== 1).map((u) => u.user_id);
      const [weights, inputs] = await Promise.all([
        deps.store.holdingWeights ? deps.store.holdingWeights(ids) : Promise.resolve(new Map()),
        paid.length > 0 && deps.store.allocationInputs ? deps.store.allocationInputs(paid) : Promise.resolve([]),
      ]);
      rows.push(...morningBriefRows(morning, weights, inputs));
    }
  }

  const earningsUsers = [jobHours.earningsTomorrow, ...jobHours.earningsResult]
    .flatMap((h) => (wanted.has(h) ? usersAt.get(h) ?? [] : []))
    .filter((u) => u.tier === "gold" && u.symbols.length > 0);
  if (earningsUsers.length > 0) {
    const today = new Date(now).toISOString().slice(0, 10);
    const provider = (await deps.store.newsProvider?.()) ?? "legacy";
    if (provider === "v2") {
      const resultUsers = jobHours.earningsResult.flatMap((h) => (wanted.has(h) ? usersAt.get(h) ?? [] : []))
        .filter((u) => u.tier === "gold" && u.symbols.length > 0);
      const symbols = [...new Set(resultUsers.flatMap((u) => u.symbols))].sort();
      const releases = symbols.length > 0 && deps.secReleases
        ? await deps.secReleases(symbols, addDays(today, -2))
        : [];
      for (const h of jobHours.earningsResult) {
        if (wanted.has(h)) rows.push(...earningsResultRows(usersAt.get(h) ?? [], releases));
      }
    } else {
      const calendar = await fetchCalendar(deps, addDays(today, -2), addDays(today, 2));
      if (wanted.has(jobHours.earningsTomorrow)) {
        const tomorrowUsers = usersAt.get(jobHours.earningsTomorrow) ?? [];
        const golds = tomorrowUsers.filter((u) => u.tier === "gold" && u.symbols.length > 0);
        // Los pesos solo si alguien presenta mañana (una consulta por corrida).
        const anyTomorrow = golds.some((u) =>
          calendar.some((e) => e.date === addDays(u.local_date, 1) && u.symbols.includes(e.symbol))
        );
        const weights = anyTomorrow && deps.store.holdingWeights
          ? await deps.store.holdingWeights(golds.map((u) => u.user_id))
          : undefined;
        rows.push(...earningsTomorrowRows(tomorrowUsers, calendar, weights));
      }
      for (const h of jobHours.earningsResult) {
        if (wanted.has(h)) rows.push(...earningsResultRows(usersAt.get(h) ?? [], calendar));
      }
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

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
//   para quien tiene el interruptor `daily_brief` (y la pieza `push`)
//   prendido, en cambio, "Tu brief de hoy está listo" de lunes a viernes
//   (`daily_brief`, spec del brief diario §3.7), y NO `morning_brief`;
// - 9:00 del día del mes que eligió → su aporte y cómo repartirlo (fase 6,
//   Premium);
// - 04:00 UTC → limpieza (push_purge) y purga del brief (videos de más de 7
//   días, briefs de más de 14).
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
  contributionReminderRows,
  jobHours,
  type BriefPushInput,
  type BriefSignal,
  briefSignals,
  type CachedHeadline,
  dailyBriefRows,
  type LocalUser,
  morningBriefRows,
  newsTickerCount,
  type OutboxInsert,
  parseFinnhubCalendar,
  weeklyReportRows,
} from "./jobs.ts";
import type { Quote } from "../market-watch/quotes.ts";
import { previousBusinessDay } from "../daily-brief/earnings.ts";
import type { JobsStore } from "./store.ts";

export type JobsDeps = Pick<Deps, "env" | "now" | "fetch"> & {
  store: JobsStore;
  /// v2: comunicados de resultados (8-K 2.02) presentados desde [since] por
  /// [symbols] (ver `secEarningsReleases`).
  secReleases?: (symbols: string[], since: string) => Promise<EarningsEntry[]>;
  /// Cotizaciones en lote (Yahoo) para el push del brief: cuánto se movió la
  /// cartera y si hubo un cierre nuevo. Sin esto no sale `daily_brief`.
  quotes?: (symbols: string[]) => Promise<Map<string, Quote>>;
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
        jobHours.contributionReminder,
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
    const eight = usersAt.get(jobHours.morningBrief) ?? [];
    // Con el interruptor del brief prendido (y la pieza `push`), el
    // `daily_brief` reemplaza al `morning_brief`. Si algo falla, se sigue como
    // hoy: es más seguro mandar el de siempre que quedarse sin nada.
    let briefUsers = new Set<string>();
    try {
      const brief = await briefPushRows(deps, eight, now);
      rows.push(...brief.rows);
      briefUsers = brief.users;
    } catch (e) {
      console.error("[daily-jobs] daily_brief", String(e));
    }
    // Con una sola acción no hay concentración ni plan que comparar.
    const morning = eight.filter((u) => u.symbols.length >= 2 && !briefUsers.has(u.user_id));
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

  if (wanted.has(jobHours.contributionReminder) && deps.store.contributionInputs) {
    const paid = (usersAt.get(jobHours.contributionReminder) ?? []).filter((u) => u.tier !== "free");
    if (paid.length > 0) {
      const inputs = await deps.store.contributionInputs(paid.map((u) => u.user_id));
      rows.push(...contributionReminderRows(paid, inputs));
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
    // La purga del brief no frena la de las notificaciones (ni al revés).
    await deps.store.purgeBrief?.().catch((e) => console.error("[daily-jobs] purgeBrief", String(e)));
  }

  if (inserted > 0 && deps.sender) {
    summary.dispatched = (await runDispatch(deps.dispatchStore, deps.sender, deps.now)).sent;
  }
  return summary;
}

/// Usuarios de las 8 que tienen el brief y su push prendidos, y las filas de
/// `daily_brief` que les tocan. Los demás siguen con `morning_brief`.
async function briefPushRows(
  deps: JobsDeps,
  eight: LocalUser[],
  now: number,
): Promise<{ rows: OutboxInsert[]; users: Set<string> }> {
  const none = { rows: [], users: new Set<string>() };
  if (!deps.store.dailyBriefInputs) return none;
  const withPortfolio = eight.filter((u) => u.symbols.length > 0);
  if (withPortfolio.length === 0) return none;
  const all = await deps.store.dailyBriefInputs(withPortfolio.map((u) => u.user_id));
  const inputs = all.filter((i) => i.brief_on && i.push_piece);
  const users = new Set(inputs.map((i) => i.user_id));
  // Sábado y domingo no hay brief (y tampoco `morning_brief` para ellos).
  const weekday = eight.filter((u) => users.has(u.user_id) && u.local_dow >= 1 && u.local_dow <= 5);
  if (weekday.length === 0) return { rows: [], users };
  // Sin cotizaciones no se sabe si hubo un cierre: se sigue con `morning_brief`.
  if (!deps.quotes) return none;

  const byUser = new Map(inputs.map((i) => [i.user_id, i]));
  const symbols = [...new Set(weekday.flatMap((u) => byUser.get(u.user_id)?.holdings.map((h) => h.symbol) ?? []))];
  const quotes = await deps.quotes(symbols);

  // Titulares: solo de la caché ya calentada, por fecha local.
  const headlineCounts = new Map<string, number>();
  if (deps.store.warmedHeadlines) {
    const byDay = new Map<string, LocalUser[]>();
    for (const u of weekday) byDay.set(u.local_date, [...(byDay.get(u.local_date) ?? []), u]);
    for (const [day, list] of byDay) {
      const syms = [...new Set(list.flatMap((u) => byUser.get(u.user_id)?.holdings.map((h) => h.symbol) ?? []))];
      const cache: Map<string, CachedHeadline[]> = await deps.store.warmedHeadlines(syms, day);
      for (const u of list) {
        headlineCounts.set(u.user_id, newsTickerCount(byUser.get(u.user_id)!.holdings.map((h) => h.symbol), cache, now));
      }
    }
  }

  // Señales de cartera (como el `morning_brief`): pesos de las tenencias y
  // plan de cartera de Premium/Gold.
  const paid = weekday.filter((u) => u.tier !== "free" && u.local_dow !== 1).map((u) => u.user_id);
  const plans = paid.length > 0 && deps.store.allocationInputs ? await deps.store.allocationInputs(paid) : [];
  const planOf = new Map(plans.map((p) => [p.user_id, p]));
  const signals = new Map<string, BriefSignal[]>();
  for (const u of weekday) {
    const weights = new Map<string, number>();
    for (const h of byUser.get(u.user_id)!.holdings) if (h.weight_pct !== null) weights.set(h.symbol, h.weight_pct);
    signals.set(u.user_id, briefSignals(u, weights, planOf.get(u.user_id)));
  }
  const month = weekday[0].local_date.slice(0, 7);
  const seenSignals = deps.store.seenBriefSignals
    ? await deps.store.seenBriefSignals(weekday.map((u) => u.user_id), month)
    : new Map<string, Set<string>>();

  // Resultados (Gold, solo con la fuente v2 = SEC): un 8-K 2.02 desde el último cierre.
  const earnings = new Map<string, number>();
  const golds = weekday.filter((u) => u.tier === "gold");
  if (golds.length > 0 && deps.secReleases && ((await deps.store.newsProvider?.()) ?? "legacy") === "v2") {
    const syms = [...new Set(golds.flatMap((u) => u.symbols))].sort();
    const since = previousBusinessDay(golds.map((u) => u.local_date).sort()[0]);
    const releases = await deps.secReleases(syms, since);
    for (const u of golds) {
      const from = previousBusinessDay(u.local_date);
      const held = new Set(u.symbols);
      const n = new Set(releases.filter((r) => held.has(r.symbol) && r.date >= from && r.date <= u.local_date).map((r) => r.symbol)).size;
      if (n > 0) earnings.set(u.user_id, n);
    }
  }

  return {
    rows: dailyBriefRows(weekday, inputs as BriefPushInput[], quotes, headlineCounts, signals, { seenSignals, earnings }),
    users,
  };
}

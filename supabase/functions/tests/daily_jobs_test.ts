// daily-jobs SIN red ni base (la parte SQL: push_notifications_db_test.sql).
//
//   deno test --allow-env tests/daily_jobs_test.ts

import { assertEquals } from "jsr:@std/assert@1";
import { handle, type JobsDeps, runDailyJobs } from "../daily-jobs/handler.ts";
import {
  earningsResultRows,
  earningsTomorrowRows,
  type LocalUser,
  type OutboxInsert,
  parseFinnhubCalendar,
  surprise,
  weeklyReportRows,
} from "../daily-jobs/jobs.ts";
import type { JobsStore } from "../daily-jobs/store.ts";
import { FakeSender, MemoryDispatchStore } from "./push_fakes.ts";

const user = (over: Partial<LocalUser> = {}): LocalUser => ({
  user_id: "u1",
  timezone: "America/Argentina/Buenos_Aires",
  local_date: "2026-10-17",
  local_dow: 6,
  tier: "gold",
  symbols: ["AAPL", "NVDA"],
  ...over,
});

const calendar = parseFinnhubCalendar({
  earningsCalendar: [
    { symbol: "AAPL", date: "2026-10-18", hour: "amc", epsActual: null, epsEstimate: 1.43 },
    { symbol: "msft", date: "2026-10-18", hour: "amc", epsActual: null, epsEstimate: 3.1 },
    { symbol: "NVDA", date: "2026-10-17", hour: "bmo", epsActual: 0.92, epsEstimate: 0.85 },
    { symbol: "KO", date: "2026-10-17", hour: "bmo", epsActual: 0.7, epsEstimate: 0.7 },
    { symbol: null, date: "2026-10-17" },
  ],
});

Deno.test("informe: solo los sábados, con posiciones y con el informe prendido", () => {
  const rows = weeklyReportRows(
    [user(), user({ user_id: "u2", local_dow: 5 }), user({ user_id: "u3", symbols: [] })],
    true,
  );
  assertEquals(rows, [{
    user_id: "u1",
    kind: "weekly_report",
    dedupe_key: "weekly_report:2026-10-12",
    data: { week_start: "2026-10-12" },
  }]);
  assertEquals(weeklyReportRows([user()], false), []);
});

Deno.test("earnings: mañana, solo Gold y solo lo que tiene, en una notificación", () => {
  const rows = earningsTomorrowRows(
    [user({ symbols: ["AAPL", "MSFT", "KO"] }), user({ user_id: "premium", tier: "premium" })],
    calendar,
  );
  assertEquals(rows.length, 1);
  assertEquals(rows[0].data, { symbols: ["AAPL", "MSFT"], date: "2026-10-18" });
  assertEquals(rows[0].dedupe_key, "earnings_tomorrow:2026-10-18");
});

Deno.test("earnings: resultados que ya salieron, con la sorpresa", () => {
  const rows = earningsResultRows([user({ symbols: ["NVDA", "KO", "AAPL"] })], calendar);
  assertEquals(rows.map((r) => r.dedupe_key).sort(), ["earnings_result:KO:2026-10-17", "earnings_result:NVDA:2026-10-17"]);
  const nvda = rows.find((r) => r.data.symbol === "NVDA")!;
  assertEquals(nvda.data.surprise, "beat");
  assertEquals(surprise(0.7, 0.7), "inline");
  assertEquals(surprise(0.5, 0.7), "miss");
  assertEquals(surprise(-0.1, -0.1), "inline");
});

class MemoryJobsStore implements JobsStore {
  users = new Map<number, LocalUser[]>();
  enqueued: OutboxInsert[] = [];
  reportOn = true;
  purges = 0;

  constructor(private readonly dispatch: MemoryDispatchStore) {}

  usersAtLocalHour(hour: number) {
    return Promise.resolve(this.users.get(hour) ?? []);
  }
  enqueue(rows: OutboxInsert[]) {
    const fresh = rows.filter((r) => !this.enqueued.some((e) => e.user_id === r.user_id && e.dedupe_key === r.dedupe_key));
    this.enqueued.push(...fresh);
    for (const r of fresh) this.dispatch.add(r.user_id, r.kind, r.data);
    return Promise.resolve(fresh.length);
  }
  weeklyReportEnabled() {
    return Promise.resolve(this.reportOn);
  }
  purge() {
    this.purges++;
    return Promise.resolve();
  }
}

function jobsDeps(nowIso: string) {
  const now = Date.parse(nowIso);
  const dispatch = new MemoryDispatchStore(() => now);
  dispatch.user("u1", { tier: "gold" });
  const store = new MemoryJobsStore(dispatch);
  const sender = new FakeSender();
  const finnhubCalls: string[] = [];
  const deps: JobsDeps = {
    env: (k) => ({ CRON_SECRET: "s3cret", FINNHUB_API_KEY: "fk" } as Record<string, string>)[k],
    now: () => now,
    fetch: ((url: string) => {
      finnhubCalls.push(url);
      return Promise.resolve(Response.json({
        earningsCalendar: [{ symbol: "AAPL", date: "2026-10-18", hour: "amc", epsActual: null, epsEstimate: 1.4 }],
      }));
    }) as typeof fetch,
    store,
    dispatchStore: dispatch,
    sender,
  };
  return { deps, store, sender, finnhubCalls };
}

Deno.test("corrida: sábado 9 encola el informe y lo manda; Finnhub solo si hay Gold con posiciones", async () => {
  // Sábado 12:00Z = 9:00 en Buenos Aires.
  const { deps, store, sender, finnhubCalls } = jobsDeps("2026-10-17T12:00:00Z");
  store.users.set(9, [user()]);
  const r = await runDailyJobs(deps);
  assertEquals(r.queued, { weekly_report: 1 });
  assertEquals(r.dispatched, 1);
  assertEquals(sender.sent[0].title, "Tu semana en Porty está lista");
  assertEquals(finnhubCalls.length, 0);

  // Otra corrida en la misma hora: no repite.
  const again = await runDailyJobs(deps);
  assertEquals(again.dispatched, 0);
});

Deno.test("corrida: 19 h de un Gold pide el calendario una vez y avisa lo de mañana", async () => {
  // Viernes 22:00Z = 19:00 en Buenos Aires.
  const { deps, store, sender, finnhubCalls } = jobsDeps("2026-10-16T22:00:00Z");
  store.users.set(19, [user({ local_date: "2026-10-17", local_dow: 5, symbols: ["AAPL"] })]);
  const r = await runDailyJobs(deps);
  assertEquals(r.queued, { earnings_tomorrow: 1 });
  assertEquals(finnhubCalls.length, 1);
  assertEquals(new URL(finnhubCalls[0]).searchParams.get("from"), "2026-10-14");
  assertEquals(sender.sent[0].title, "AAPL presenta resultados mañana");
});

Deno.test("corrida: limpieza a las 4 UTC, y el handler exige el secreto", async () => {
  const { deps, store } = jobsDeps("2026-10-16T04:00:00Z");
  await runDailyJobs(deps);
  assertEquals(store.purges, 1);
  const req = (secret?: string, body?: unknown) =>
    new Request("http://local/functions/v1/daily-jobs", {
      method: "POST",
      headers: secret ? { "x-cron-secret": secret } : {},
      body: body ? JSON.stringify(body) : undefined,
    });
  assertEquals((await handle(req(), deps)).status, 401);
  const only = await (await handle(req("s3cret", { hours: [9] }), deps)).json();
  assertEquals(only.hours, [9]);
  // Con horas puntuales (prueba manual) no limpia.
  assertEquals(only.purged, false);
});

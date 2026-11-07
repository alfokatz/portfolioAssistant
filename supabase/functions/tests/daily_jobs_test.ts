// daily-jobs SIN red ni base (la parte SQL: push_notifications_db_test.sql).
//
//   deno test --allow-env tests/daily_jobs_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import { handle, type JobsDeps, runDailyJobs } from "../daily-jobs/handler.ts";
import {
  type AllocationInput,
  allocationDrift,
  type ContributionInput,
  contributionReminderRows,
  contributionSplit,
  allocationDriftRows,
  earningsResultRows,
  earningsTomorrowRows,
  type LocalUser,
  morningBriefRows,
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
  assertEquals(rows[0].data, {
    symbols: ["AAPL", "MSFT"],
    date: "2026-10-18",
    items: [
      { symbol: "AAPL", weight_pct: null, eps_estimate: 1.43, hour: "amc" },
      { symbol: "MSFT", weight_pct: null, eps_estimate: 3.1, hour: "amc" },
    ],
  });
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
  provider = "legacy";
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
  newsProvider() {
    return Promise.resolve(this.provider);
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

Deno.test("v2 (SEC): sin consenso, la push dice que presentó y no inventa la sorpresa", () => {
  const rows = earningsResultRows(
    [user({ symbols: ["NVDA", "KO"] })],
    [
      { symbol: "NVDA", date: "2026-10-17", hour: null, epsActual: null, epsEstimate: null, reported: true },
      { symbol: "KO", date: "2026-10-10", hour: null, epsActual: null, epsEstimate: null, reported: true },
    ],
  );
  assertEquals(rows.length, 1);
  assertEquals(rows[0].data, {
    symbol: "NVDA",
    date: "2026-10-17",
    eps_actual: null,
    eps_estimate: null,
    surprise: "reported",
  });
});

Deno.test("corrida v2: no avisa 'mañana' (fecha estimada) y los resultados salen de la SEC", async () => {
  // Viernes 22:00Z = 19:00 en Buenos Aires: hora de "mañana" y de resultados.
  const { deps, store, sender, finnhubCalls } = jobsDeps("2026-10-16T22:00:00Z");
  store.provider = "v2";
  const asked: { symbols: string[]; since: string }[] = [];
  deps.secReleases = (symbols, since) => {
    asked.push({ symbols, since });
    return Promise.resolve([
      { symbol: "AAPL", date: "2026-10-16", hour: null, epsActual: null, epsEstimate: null, reported: true },
    ]);
  };
  store.users.set(19, [user({ local_date: "2026-10-16", local_dow: 5, symbols: ["AAPL"] })]);
  const r = await runDailyJobs(deps);
  assertEquals(finnhubCalls.length, 0);
  assertEquals(asked, [{ symbols: ["AAPL"], since: "2026-10-14" }]);
  assertEquals(r.queued, { earnings_result: 1 });
  assertEquals(sender.sent[0].title, "AAPL presentó resultados");
  assertEquals(sender.sent[0].body, "Ya publicó sus resultados del trimestre. Tocá para ver cómo le fue.");
});

// ── Plan de cartera (F3 de 2026-10-16-porty-siguiente-nivel.md) ──

const plan = (over: Partial<AllocationInput> = {}): AllocationInput => ({
  user_id: "u1",
  targets: { VOO: 60, BND: 40 },
  drift_threshold: 5,
  holdings: [
    { symbol: "VOO", quantity: 10, price: 500 }, // 5000
    { symbol: "BND", quantity: 20, price: 70 }, // 1400
    { symbol: "NVDA", quantity: 1, price: 600 }, // 600, sin objetivo
  ],
  ...over,
});

Deno.test("plan: desvío contra el objetivo, lo que no tiene objetivo cuenta con 0", () => {
  const d = allocationDrift(plan());
  // Total 7000: VOO 71.4%, BND 20%, NVDA 8.6%.
  assertEquals(d, [
    { symbol: "BND", current_pct: 20, target_pct: 40 },
    { symbol: "VOO", current_pct: 71.4, target_pct: 60 },
    { symbol: "NVDA", current_pct: 8.6, target_pct: 0 },
  ]);
  // Sin precios no hay desvío que calcular.
  assertEquals(allocationDrift(plan({ holdings: [{ symbol: "VOO", quantity: 1, price: null }] })), []);
});

Deno.test("plan: avisa los lunes si pasa el umbral, una vez por semana", () => {
  const monday = user({ local_dow: 1, local_date: "2026-10-19", tier: "premium" });
  const rows = allocationDriftRows([monday, user({ user_id: "u2", local_dow: 2 })], [plan()]);
  assertEquals(rows.length, 1);
  assertEquals(rows[0].kind, "allocation_drift");
  assertEquals(rows[0].dedupe_key, "allocation_drift:2026-10-19");
  assertEquals((rows[0].data.items as unknown[]).length, 3);
  // Dentro del umbral: nada.
  const tight = plan({ targets: { VOO: 70, BND: 20, NVDA: 10 } });
  assertEquals(allocationDriftRows([monday], [tight]), []);
});

Deno.test("desvío mensual: solo el primer lunes del mes", () => {
  const monthly = plan({ notify_frequency: "monthly" });
  const first = user({ local_dow: 1, local_date: "2026-11-02" });
  const third = user({ local_dow: 1, local_date: "2026-10-19" });
  assertEquals(allocationDriftRows([first], [monthly]).length, 1);
  assertEquals(allocationDriftRows([third], [monthly]), []);
  // Semanal (o sin dato): todos los lunes.
  assertEquals(allocationDriftRows([third], [plan({ notify_frequency: "weekly" })]).length, 1);
  assertEquals(allocationDriftRows([third], [plan({ notify_frequency: null })]).length, 1);
});

Deno.test("corrida: lunes 10 lee los planes solo de Premium/Gold con posiciones", async () => {
  const { deps, store } = jobsDeps("2026-10-19T13:00:00Z");
  const asked: string[][] = [];
  store.users.set(10, [
    user({ local_dow: 1, local_date: "2026-10-19", tier: "premium" }),
    user({ user_id: "free", local_dow: 1, local_date: "2026-10-19", tier: "free" }),
  ]);
  const withPlans = store as unknown as { allocationInputs: (ids: string[]) => Promise<AllocationInput[]> };
  withPlans.allocationInputs = (ids) => {
    asked.push(ids);
    return Promise.resolve([plan()]);
  };
  const summary = await runDailyJobs(deps, [10]);
  assertEquals(asked, [["u1"]]);
  assertEquals(summary.queued, { allocation_drift: 1 });
});

// ── Resumen antes de los resultados (F5 de 2026-10-16-porty-siguiente-nivel.md) ──

Deno.test("earnings: mañana lleva cuánto pesa cada una en la cartera", () => {
  const weights = new Map([["u1", new Map([["AAPL", 18.4], ["MSFT", 6]])]]);
  const rows = earningsTomorrowRows([user({ symbols: ["AAPL", "MSFT"] })], calendar, weights);
  const items = rows[0].data.items as { symbol: string; weight_pct: number }[];
  assertEquals(items.map((i) => [i.symbol, i.weight_pct]), [["AAPL", 18.4], ["MSFT", 6]]);
});

Deno.test("corrida: 19 h pide los pesos una vez y solo si alguien presenta mañana", async () => {
  const { deps, store } = jobsDeps("2026-10-17T22:00:00Z");
  store.users.set(19, [user({ symbols: ["AAPL"] }), user({ user_id: "u9", symbols: ["KO"] })]);
  const asked: string[][] = [];
  const withWeights = store as unknown as { holdingWeights: (ids: string[]) => Promise<Map<string, Map<string, number>>> };
  withWeights.holdingWeights = (ids) => {
    asked.push(ids);
    return Promise.resolve(new Map([["u1", new Map([["AAPL", 22]])]]));
  };
  await runDailyJobs(deps, [19]);
  assertEquals(asked, [["u1", "u9"]]);
  const row = store.enqueued.find((r) => r.kind === "earnings_tomorrow")!;
  assertEquals((row.data.items as { weight_pct: number }[])[0].weight_pct, 22);
});

// ── Resumen de la mañana (fase 2 de 2026-10-24-porty-en-toda-la-app.md) ──

const weightsOf = (entries: Record<string, Record<string, number>>) =>
  new Map(Object.entries(entries).map(([u, w]) => [u, new Map(Object.entries(w))]));

const tuesday = (over: Partial<LocalUser> = {}) =>
  user({ local_dow: 2, local_date: "2026-10-20", tier: "premium", ...over });

Deno.test("resumen: concentración desde 25% (como la app), nunca con una sola acción", () => {
  const rows = morningBriefRows(
    [tuesday(), tuesday({ user_id: "solo" }), tuesday({ user_id: "spread" })],
    weightsOf({
      u1: { NVDA: 62, AAPL: 38 },
      solo: { NVDA: 100 },
      spread: { A: 20, B: 20, C: 20, D: 20, E: 20 },
    }),
    [],
  );
  assertEquals(rows.length, 1);
  assertEquals(rows[0].kind, "morning_brief");
  assertEquals(rows[0].dedupe_key, "morning_brief:2026-10:concentration:NVDA");
  assertEquals(rows[0].data, {
    signals: [{ kind: "concentration", symbol: "NVDA", weight_pct: 62 }],
    count: 1,
  });
});

Deno.test("resumen: el desvío del plan va primero (Premium); los lunes lo avisa allocation_drift; Free no lo tiene", () => {
  const weights = weightsOf({ u1: { VOO: 71.4, BND: 20, NVDA: 8.6 } });
  const [paid] = morningBriefRows([tuesday()], weights, [plan()]);
  const signals = paid.data.signals as { kind: string; symbol: string }[];
  assertEquals(signals.map((s) => `${s.kind}:${s.symbol}`), ["drift:BND", "concentration:VOO"]);
  assertEquals(paid.dedupe_key, "morning_brief:2026-10:concentration:VOO|drift:BND");

  const monday = morningBriefRows([tuesday({ local_dow: 1, local_date: "2026-10-19" })], weights, [plan()]);
  assertEquals((monday[0].data.signals as { kind: string }[]).map((s) => s.kind), ["concentration"]);

  const free = morningBriefRows([tuesday({ tier: "free" })], weights, [plan()]);
  assertEquals((free[0].data.signals as { kind: string }[]).map((s) => s.kind), ["concentration"]);
});

Deno.test("resumen: lo mismo no se repite en el mes; algo nuevo sí avisa", () => {
  const weights = weightsOf({ u1: { NVDA: 62, AAPL: 38 } });
  const day1 = morningBriefRows([tuesday()], weights, [])[0];
  const day2 = morningBriefRows([tuesday({ local_date: "2026-10-21", local_dow: 3 })], weights, [])[0];
  assertEquals(day1.dedupe_key, day2.dedupe_key);
  const nextMonth = morningBriefRows([tuesday({ local_date: "2026-11-03" })], weights, [])[0];
  assert(nextMonth.dedupe_key !== day1.dedupe_key);
  const withDrift = morningBriefRows([tuesday()], weights, [plan()])[0];
  assert(withDrift.dedupe_key !== day1.dedupe_key);
});

Deno.test("corrida: 8 h pide los pesos de quien tiene 2+ acciones y los planes solo de los pagos", async () => {
  const { deps, store } = jobsDeps("2026-10-20T11:00:00Z");
  store.users.set(8, [
    tuesday(),
    tuesday({ user_id: "free", tier: "free" }),
    tuesday({ user_id: "solo", symbols: ["NVDA"] }),
  ]);
  const askedWeights: string[][] = [];
  const askedPlans: string[][] = [];
  const s = store as unknown as {
    holdingWeights: (ids: string[]) => Promise<Map<string, Map<string, number>>>;
    allocationInputs: (ids: string[]) => Promise<AllocationInput[]>;
  };
  s.holdingWeights = (ids) => {
    askedWeights.push(ids);
    return Promise.resolve(weightsOf({ u1: { NVDA: 62, AAPL: 38 }, free: { NVDA: 30, AAPL: 30, KO: 40 } }));
  };
  s.allocationInputs = (ids) => {
    askedPlans.push(ids);
    return Promise.resolve([]);
  };
  const summary = await runDailyJobs(deps, [8]);
  assertEquals(askedWeights, [["u1", "free"]]);
  assertEquals(askedPlans, [["u1"]]);
  assertEquals(summary.queued, { morning_brief: 2 });
});

// ── Recordatorio de aporte (fase 6) ──

const contribution = (over: Partial<ContributionInput> = {}): ContributionInput => ({
  user_id: "u1",
  targets: { VOO: 60, BND: 40 },
  contribution_day: 20,
  contribution_amount: 500,
  holdings: [
    { symbol: "VOO", quantity: 10, price: 500 }, // 5000
    { symbol: "BND", quantity: 20, price: 70 }, // 1400
    { symbol: "NVDA", quantity: 1, price: 600 }, // 600, sin objetivo
  ],
  ...over,
});

Deno.test("aporte: el mismo reparto que la app, solo compras y sumando el aporte", () => {
  // Total 7000 + 500 = 7500. A VOO le faltan max(0, 4500 − 5000) = 0; a BND,
  // 3000 − 1400 = 1600: todo a BND.
  assertEquals(contributionSplit(contribution().holdings, { VOO: 60, BND: 40 }, 500), [
    { symbol: "BND", amount: 500 },
  ]);
  // Sin nada todavía: según los objetivos.
  assertEquals(contributionSplit([], { VOO: 60, BND: 40 }, 1000), [
    { symbol: "VOO", amount: 600 },
    { symbol: "BND", amount: 400 },
  ]);
  // A los dos les falta: en proporción a lo que les falta, y suma el aporte.
  const split = contributionSplit(
    [{ symbol: "VOO", quantity: 1, price: 300 }, { symbol: "BND", quantity: 1, price: 300 }],
    { VOO: 70, BND: 30 },
    400,
  );
  // Después: 1000 → VOO 700 (faltan 400), BND 300 (faltan 0).
  assertEquals(split, [{ symbol: "VOO", amount: 400 }]);
  assertEquals(contributionSplit([], {}, 500), []);
  assertEquals(contributionSplit([], { VOO: 100 }, 0), []);
});

Deno.test("aporte: solo el día que eligió (fecha local), una vez por mes; sin monto, sin reparto", () => {
  const day20 = user({ local_date: "2026-10-20", tier: "premium" });
  const rows = contributionReminderRows([day20, user({ user_id: "u2", local_date: "2026-10-20" })], [contribution()]);
  assertEquals(rows.length, 1);
  assertEquals(rows[0].kind, "contribution_reminder");
  assertEquals(rows[0].dedupe_key, "contribution_reminder:2026-10");
  assertEquals(rows[0].data, { amount: 500, split: [{ symbol: "BND", amount: 500 }], more: 0 });

  assertEquals(contributionReminderRows([user({ local_date: "2026-10-21" })], [contribution()]), []);
  const noAmount = contributionReminderRows([day20], [contribution({ contribution_amount: null })]);
  assertEquals(noAmount[0].data, { amount: null, split: [], more: 0 });
});

Deno.test("corrida: 9 h lee los recordatorios solo de Premium/Gold", async () => {
  const { deps, store } = jobsDeps("2026-10-20T12:00:00Z");
  store.users.set(9, [
    user({ local_date: "2026-10-20", local_dow: 2, tier: "premium" }),
    user({ user_id: "free", local_date: "2026-10-20", local_dow: 2, tier: "free" }),
  ]);
  const asked: string[][] = [];
  const s = store as unknown as { contributionInputs: (ids: string[]) => Promise<ContributionInput[]> };
  s.contributionInputs = (ids) => {
    asked.push(ids);
    return Promise.resolve([contribution()]);
  };
  const summary = await runDailyJobs(deps, [9]);
  assertEquals(asked, [["u1"]]);
  assertEquals(summary.queued, { contribution_reminder: 1 });
});

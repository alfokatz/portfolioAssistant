// Qué encolar en cada hora local (puro). Los usuarios llegan de
// `push_users_at_local_hour`; el despacho decide después (preferencias,
// silencio, tope).

export type LocalUser = {
  user_id: string;
  timezone: string;
  /// "YYYY-MM-DD" en su zona.
  local_date: string;
  /// 0 = domingo … 6 = sábado.
  local_dow: number;
  tier: string;
  symbols: string[];
};

export type OutboxInsert = {
  user_id: string;
  kind: string;
  dedupe_key: string;
  data: Record<string, unknown>;
};

export type EarningsEntry = {
  symbol: string;
  /// "YYYY-MM-DD" (fecha de EE.UU.).
  date: string;
  /// bmo (antes de la apertura), amc (después del cierre), dmh.
  hour: string | null;
  epsActual: number | null;
  epsEstimate: number | null;
  /// v2 (SEC): hay un comunicado de resultados presentado (8-K 2.02) aunque
  /// no se sepa el EPS ni lo esperado.
  reported?: boolean;
};

/// A qué hora local corre cada cosa.
export const jobHours = {
  weeklyReport: 9,
  /// Los lunes: la cartera se alejó del plan del usuario (Premium).
  allocationDrift: 10,
  earningsTomorrow: 19,
  /// Los resultados se miran dos veces (los de antes de la apertura y los de
  /// después del cierre del día anterior); la clave de duplicados evita
  /// repetir.
  earningsResult: [12, 19],
  /// Todos los días: lo que Porty marca en la cartera (si hay algo nuevo).
  morningBrief: 8,
  /// El día del mes que eligió el usuario: su aporte y cómo repartirlo.
  contributionReminder: 9,
};

export function addDays(date: string, days: number): string {
  const d = new Date(`${date}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/// Sábado a las 9: el informe de la semana que cerró (lunes = sábado - 5).
export function weeklyReportRows(users: LocalUser[], reportEnabled: boolean): OutboxInsert[] {
  if (!reportEnabled) return [];
  return users
    .filter((u) => u.local_dow === 6 && u.symbols.length > 0)
    .map((u) => {
      const weekStart = addDays(u.local_date, -5);
      return {
        user_id: u.user_id,
        kind: "weekly_report",
        dedupe_key: `weekly_report:${weekStart}`,
        data: { week_start: weekStart },
      };
    });
}

const isGold = (u: LocalUser) => u.tier === "gold";

/// Peso (%) de cada acción en la cartera de cada usuario
/// (`push_holding_weights`): usuario → símbolo → peso.
export type HoldingWeights = Map<string, Map<string, number>>;

/// Las acciones de su cartera que presentan resultados mañana, en una sola
/// notificación, con lo que hace falta para el resumen: cuánto pesa cada
/// una, la ganancia por acción esperada y si es antes o después del
/// mercado (F5 de 2026-10-16-porty-siguiente-nivel.md).
export function earningsTomorrowRows(
  users: LocalUser[],
  calendar: EarningsEntry[],
  weights: HoldingWeights = new Map(),
): OutboxInsert[] {
  const out: OutboxInsert[] = [];
  for (const u of users.filter(isGold)) {
    const tomorrow = addDays(u.local_date, 1);
    const held = new Set(u.symbols);
    const entries = new Map<string, EarningsEntry>();
    for (const e of calendar) {
      if (e.date === tomorrow && held.has(e.symbol) && !entries.has(e.symbol)) entries.set(e.symbol, e);
    }
    const symbols = [...entries.keys()].sort();
    if (symbols.length === 0) continue;
    const userWeights = weights.get(u.user_id);
    out.push({
      user_id: u.user_id,
      kind: "earnings_tomorrow",
      dedupe_key: `earnings_tomorrow:${tomorrow}`,
      data: {
        symbols,
        date: tomorrow,
        items: symbols.map((symbol) => ({
          symbol,
          weight_pct: userWeights?.get(symbol) ?? null,
          eps_estimate: entries.get(symbol)!.epsEstimate,
          hour: entries.get(symbol)!.hour,
        })),
      },
    });
  }
  return out;
}

/// beat / miss / inline: más de 2% de diferencia con lo esperado cuenta.
export function surprise(actual: number, estimate: number): "beat" | "miss" | "inline" {
  const band = Math.max(Math.abs(estimate) * 0.02, 0.01);
  if (actual > estimate + band) return "beat";
  if (actual < estimate - band) return "miss";
  return "inline";
}

export function earningsResultRows(users: LocalUser[], calendar: EarningsEntry[]): OutboxInsert[] {
  const out: OutboxInsert[] = [];
  for (const u of users.filter(isGold)) {
    const days = new Set([u.local_date, addDays(u.local_date, -1)]);
    const held = new Set(u.symbols);
    for (const e of calendar) {
      if (!held.has(e.symbol) || !days.has(e.date)) continue;
      if (e.epsActual === null && !e.reported) continue;
      out.push({
        user_id: u.user_id,
        kind: "earnings_result",
        dedupe_key: `earnings_result:${e.symbol}:${e.date}`,
        data: {
          symbol: e.symbol,
          date: e.date,
          eps_actual: e.epsActual,
          eps_estimate: e.epsEstimate,
          surprise: e.epsActual === null || e.epsEstimate === null
            ? (e.reported ? "reported" : "inline")
            : surprise(e.epsActual, e.epsEstimate),
        },
      });
    }
  }
  return out;
}

export function parseFinnhubCalendar(body: unknown): EarningsEntry[] {
  const list = (body as { earningsCalendar?: unknown[] })?.earningsCalendar;
  if (!Array.isArray(list)) return [];
  const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : null);
  return (list as Record<string, unknown>[])
    .filter((e) => typeof e.symbol === "string" && typeof e.date === "string")
    .map((e) => ({
      symbol: (e.symbol as string).toUpperCase(),
      date: e.date as string,
      hour: typeof e.hour === "string" ? e.hour : null,
      epsActual: num(e.epsActual),
      epsEstimate: num(e.epsEstimate),
    }));
}

/// El plan de cartera de un usuario y lo que tiene (de
/// `allocation_drift_inputs`).
export type AllocationInput = {
  user_id: string;
  /// {SÍMBOLO: porcentaje}, suman 100.
  targets: Record<string, number>;
  /// Puntos de desvío que disparan el aviso.
  drift_threshold: number;
  /// "weekly": todos los lunes; "monthly": el primer lunes del mes. Sin
  /// dato (base sin la migración de la frecuencia), semanal.
  notify_frequency?: "weekly" | "monthly" | null;
  holdings: { symbol: string; quantity: number; price: number | null }[];
};

export type DriftItem = { symbol: string; current_pct: number; target_pct: number };

/// Peso actual contra objetivo de cada símbolo (lo que tiene sin objetivo
/// cuenta con objetivo 0), del más desviado al menos. Vacío si no se puede
/// valuar la cartera.
export function allocationDrift(input: AllocationInput): DriftItem[] {
  const values = new Map<string, number>();
  for (const h of input.holdings) {
    const symbol = h.symbol.toUpperCase();
    if (!(h.quantity > 0) || h.price === null || !(h.price > 0)) continue;
    values.set(symbol, (values.get(symbol) ?? 0) + h.quantity * h.price);
  }
  const total = [...values.values()].reduce((a, b) => a + b, 0);
  if (!(total > 0)) return [];
  const symbols = new Set([...values.keys(), ...Object.keys(input.targets).map((s) => s.toUpperCase())]);
  const targetOf = (s: string) => Number(Object.entries(input.targets).find(([k]) => k.toUpperCase() === s)?.[1] ?? 0);
  return [...symbols]
    .map((symbol) => ({
      symbol,
      current_pct: round1(((values.get(symbol) ?? 0) / total) * 100),
      target_pct: round1(targetOf(symbol)),
    }))
    .sort((a, b) =>
      Math.abs(b.current_pct - b.target_pct) - Math.abs(a.current_pct - a.target_pct) ||
      a.symbol.localeCompare(b.symbol)
    );
}

/// Lunes a las 10: si algo se alejó del plan más que el umbral, un aviso con
/// lo que más se desvió (hasta 3). Uno por semana, o uno por mes (el primer
/// lunes) si el usuario lo eligió así.
export function allocationDriftRows(users: LocalUser[], inputs: AllocationInput[]): OutboxInsert[] {
  const byUser = new Map(inputs.map((i) => [i.user_id, i]));
  const out: OutboxInsert[] = [];
  for (const u of users) {
    if (u.local_dow !== 1) continue;
    const input = byUser.get(u.user_id);
    if (!input) continue;
    if (input.notify_frequency === "monthly" && Number(u.local_date.slice(8, 10)) > 7) continue;
    const drift = allocationDrift(input);
    const over = drift.filter((d) => Math.abs(d.current_pct - d.target_pct) >= input.drift_threshold);
    if (over.length === 0) continue;
    out.push({
      user_id: u.user_id,
      kind: "allocation_drift",
      dedupe_key: `allocation_drift:${u.local_date}`,
      data: { items: over.slice(0, 3), threshold: input.drift_threshold },
    });
  }
  return out;
}

function round1(v: number): number {
  return Math.round(v * 10) / 10;
}

/// Una cosa que Porty marca en el resumen de la mañana. Los mismos umbrales
/// que la bandeja de la app (`PortyInsightsBuilder`): ahí el usuario ve el
/// detalle al tocar la notificación.
export type BriefSignal =
  | { kind: "concentration"; symbol: string; weight_pct: number }
  | { kind: "drift"; symbol: string; current_pct: number; target_pct: number };

/// Peso desde el que una sola acción es concentración (como la app).
export const concentrationPct = 25;

function signalId(s: BriefSignal): string {
  return `${s.kind}:${s.symbol}`;
}

/// Las 8 de cada día: lo que Porty ve en la cartera, de lo más importante a
/// lo menos (el desvío del plan antes que la concentración, como en la
/// app). Sale una vez por mes por cada conjunto de señales: lo mismo no se
/// repite todos los días, pero algo nuevo sí avisa. Los lunes el desvío lo
/// avisa `allocation_drift` a las 10: no va dos veces.
export function morningBriefRows(
  users: LocalUser[],
  weights: HoldingWeights,
  inputs: AllocationInput[],
): OutboxInsert[] {
  const plans = new Map(inputs.map((i) => [i.user_id, i]));
  const out: OutboxInsert[] = [];
  for (const u of users) {
    const signals: BriefSignal[] = [];

    const input = plans.get(u.user_id);
    if (input && u.tier !== "free" && u.local_dow !== 1) {
      const worst = allocationDrift(input)[0];
      if (worst && Math.abs(worst.current_pct - worst.target_pct) >= input.drift_threshold) {
        signals.push({ kind: "drift", ...worst });
      }
    }

    const mine = weights.get(u.user_id);
    if (mine && mine.size >= 2) {
      const [symbol, weight] = [...mine.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0];
      if (weight >= concentrationPct) {
        signals.push({ kind: "concentration", symbol, weight_pct: round1(weight) });
      }
    }

    if (signals.length === 0) continue;
    const ids = signals.map(signalId).sort().join("|");
    out.push({
      user_id: u.user_id,
      kind: "morning_brief",
      dedupe_key: `morning_brief:${u.local_date.slice(0, 7)}:${ids}`,
      data: { signals, count: signals.length },
    });
  }
  return out;
}

/// Un plan con recordatorio de aporte (de `contribution_reminder_inputs`).
export type ContributionInput = {
  user_id: string;
  targets: Record<string, number>;
  /// 1-28.
  contribution_day: number;
  /// Cuánto aporta; null si no lo dijo (el aviso sale igual, sin reparto).
  contribution_amount: number | null;
  holdings: { symbol: string; quantity: number; price: number | null }[];
};

/// Cómo repartir [amount] para acercarse al plan, solo con compras. El
/// mismo cálculo que la app (`AllocationMath.contribution`): a cada ticker
/// le falta max(0, objetivo·(total + aporte) − valor), y el aporte se
/// reparte en proporción a lo que falta. De mayor a menor, en centavos.
export function contributionSplit(
  holdings: ContributionInput["holdings"],
  targets: Record<string, number>,
  amount: number,
): { symbol: string; amount: number }[] {
  if (!(amount > 0)) return [];
  const targetSum = Object.values(targets).reduce((a, b) => a + (b > 0 ? b : 0), 0);
  if (!(targetSum > 0)) return [];
  const values = new Map<string, number>();
  for (const h of holdings) {
    if (!(h.quantity > 0) || h.price === null || !(h.price > 0)) continue;
    const s = h.symbol.toUpperCase();
    values.set(s, (values.get(s) ?? 0) + h.quantity * h.price);
  }
  const total = [...values.values()].reduce((a, b) => a + b, 0);
  const after = total + amount;
  const missing = Object.entries(targets)
    .filter(([, t]) => t > 0)
    .map(([symbol, t]) => ({
      symbol: symbol.toUpperCase(),
      missing: Math.max(0, (t / targetSum) * after - (values.get(symbol.toUpperCase()) ?? 0)),
    }));
  const missingSum = missing.reduce((a, m) => a + m.missing, 0);
  if (!(missingSum > 0)) return [];
  return missing
    .filter((m) => m.missing > 0)
    .map((m) => ({ symbol: m.symbol, amount: Math.round((amount * m.missing / missingSum) * 100) / 100 }))
    .sort((a, b) => b.amount - a.amount || a.symbol.localeCompare(b.symbol));
}

/// El día que eligió cada usuario (fecha local): su aporte y el reparto
/// (hasta 4 tickers). Uno por mes.
export function contributionReminderRows(users: LocalUser[], inputs: ContributionInput[]): OutboxInsert[] {
  const byUser = new Map(inputs.map((i) => [i.user_id, i]));
  const out: OutboxInsert[] = [];
  for (const u of users) {
    const input = byUser.get(u.user_id);
    if (!input) continue;
    if (Number(u.local_date.slice(8, 10)) !== Number(input.contribution_day)) continue;
    const amount = input.contribution_amount === null ? null : Number(input.contribution_amount);
    const split = amount === null ? [] : contributionSplit(input.holdings, input.targets, amount);
    out.push({
      user_id: u.user_id,
      kind: "contribution_reminder",
      dedupe_key: `contribution_reminder:${u.local_date.slice(0, 7)}`,
      data: { amount, split: split.slice(0, 4), more: Math.max(0, split.length - 4) },
    });
  }
  return out;
}

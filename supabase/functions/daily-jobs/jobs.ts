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
};

/// A qué hora local corre cada cosa.
export const jobHours = {
  weeklyReport: 9,
  earningsTomorrow: 19,
  /// Los resultados se miran dos veces (los de antes de la apertura y los de
  /// después del cierre del día anterior); la clave de duplicados evita
  /// repetir.
  earningsResult: [12, 19],
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

/// Las acciones de su cartera que presentan resultados mañana, en una sola
/// notificación.
export function earningsTomorrowRows(users: LocalUser[], calendar: EarningsEntry[]): OutboxInsert[] {
  const out: OutboxInsert[] = [];
  for (const u of users.filter(isGold)) {
    const tomorrow = addDays(u.local_date, 1);
    const held = new Set(u.symbols);
    const symbols = [...new Set(calendar.filter((e) => e.date === tomorrow && held.has(e.symbol)).map((e) => e.symbol))]
      .sort();
    if (symbols.length === 0) continue;
    out.push({
      user_id: u.user_id,
      kind: "earnings_tomorrow",
      dedupe_key: `earnings_tomorrow:${tomorrow}`,
      data: { symbols, date: tomorrow },
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
      if (!held.has(e.symbol) || !days.has(e.date) || e.epsActual === null) continue;
      out.push({
        user_id: u.user_id,
        kind: "earnings_result",
        dedupe_key: `earnings_result:${e.symbol}:${e.date}`,
        data: {
          symbol: e.symbol,
          date: e.date,
          eps_actual: e.epsActual,
          eps_estimate: e.epsEstimate,
          surprise: e.epsEstimate === null ? "inline" : surprise(e.epsActual, e.epsEstimate),
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

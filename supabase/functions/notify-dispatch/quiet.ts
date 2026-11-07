// Hora local de un usuario y horario de silencio.

/// Minutos desde la medianoche en [timeZone] (0–1439). Zona inválida → UTC.
export function localMinutes(nowMs: number, timeZone: string): number {
  const parts = localParts(nowMs, timeZone);
  return parts.hour * 60 + parts.minute;
}

export type LocalParts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  /// 0 = domingo … 6 = sábado.
  weekday: number;
};

const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export function localParts(nowMs: number, timeZone: string): LocalParts {
  let fmt: Intl.DateTimeFormat;
  try {
    fmt = new Intl.DateTimeFormat("en-US", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      weekday: "short",
      hourCycle: "h23",
    });
  } catch {
    return localParts(nowMs, "UTC");
  }
  const get = (type: string) => fmt.formatToParts(new Date(nowMs)).find((p) => p.type === type)?.value ?? "0";
  return {
    year: Number(get("year")),
    month: Number(get("month")),
    day: Number(get("day")),
    hour: Number(get("hour")) % 24,
    minute: Number(get("minute")),
    weekday: weekdays.indexOf(get("weekday")),
  };
}

/// "YYYY-MM-DD" en [timeZone].
export function localDate(nowMs: number, timeZone: string): string {
  const p = localParts(nowMs, timeZone);
  return `${p.year}-${String(p.month).padStart(2, "0")}-${String(p.day).padStart(2, "0")}`;
}

/// "22:00" o "22:00:00" → minutos.
export function parseClock(value: string): number {
  const [h, m] = value.split(":").map((x) => Number(x));
  if (!Number.isFinite(h) || !Number.isFinite(m)) return 0;
  return ((h * 60 + m) % 1440 + 1440) % 1440;
}

/// Si [nowMs] cae en el silencio, cuándo termina (ms); si no, null.
/// Inicio == fin: sin silencio. El silencio puede cruzar la medianoche.
export function quietEndsAt(
  nowMs: number,
  timeZone: string,
  quietStart: string,
  quietEnd: string,
): number | null {
  const start = parseClock(quietStart);
  const end = parseClock(quietEnd);
  if (start === end) return null;
  const m = localMinutes(nowMs, timeZone);
  const inside = start < end ? m >= start && m < end : m >= start || m < end;
  if (!inside) return null;
  const minutesLeft = (end - m + 1440) % 1440;
  // Al minuto en punto (se pierden los segundos de ahora: hasta 59 s antes).
  const flooredNow = nowMs - (nowMs % 60_000);
  return flooredNow + minutesLeft * 60_000;
}

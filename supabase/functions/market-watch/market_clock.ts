// Horario del mercado de EE.UU. (NYSE/Nasdaq): lunes a viernes de 9:30 a
// 16:00 en Nueva York. Los feriados no están: ese día Yahoo responde
// `marketState` distinto de REGULAR y los movimientos no se evalúan.

import { localDate, localParts } from "../notify-dispatch/quiet.ts";

export const marketTimeZone = "America/New_York";

export type MarketPhase =
  /// Fin de semana o fuera de 9:30–16:10.
  | "closed"
  /// Los primeros 30 minutos: solo alertas (el salto de apertura se
  /// corrige seguido; plan §4.3).
  | "opening"
  | "open";

export function marketPhase(nowMs: number): MarketPhase {
  const p = localParts(nowMs, marketTimeZone);
  if (p.weekday === 0 || p.weekday === 6) return "closed";
  const m = p.hour * 60 + p.minute;
  // Hasta las 16:10: la última corrida toma el precio de cierre.
  if (m < 9 * 60 + 30 || m > 16 * 60 + 10) return "closed";
  if (m < 10 * 60) return "opening";
  return "open";
}

/// "YYYY-MM-DD" en Nueva York (el día de mercado).
export function marketDate(nowMs: number): string {
  return localDate(nowMs, marketTimeZone);
}

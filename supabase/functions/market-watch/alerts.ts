// Evaluación de las alertas de precio (pura). La registra
// `price_alerts_record` (20261011010000_price_alerts.sql).

export type AlertRow = {
  id: string;
  user_id: string;
  symbol: string;
  condition: "above" | "below" | "pct_up" | "pct_down";
  target: number;
  reference_price: number | null;
  repeat: "once" | "daily";
  rearm_ready: boolean;
  triggered_at: string | null;
};

export type AlertUpdate = {
  id: string;
  price: number;
  fire: boolean;
  rearm_ready: boolean;
  /// Fecha de mercado (ET) del disparo: la clave de duplicados.
  fired_on: string;
};

/// Histéresis de las alertas diarias: para volver a avisar, el precio tiene
/// que haber vuelto al menos 1% del otro lado.
export const rearmBand = 0.01;

export function thresholdPrice(a: Pick<AlertRow, "condition" | "target" | "reference_price">): number | null {
  switch (a.condition) {
    case "above":
    case "below":
      return a.target;
    case "pct_up":
      return a.reference_price ? a.reference_price * (1 + a.target / 100) : null;
    case "pct_down":
      return a.reference_price ? a.reference_price * (1 - a.target / 100) : null;
  }
}

const isUp = (c: AlertRow["condition"]) => c === "above" || c === "pct_up";

/// [marketDate]: "YYYY-MM-DD" en Nueva York. [triggeredOn]: la fecha (ET)
/// de `triggered_at`, si hay.
export function evaluateAlert(
  alert: AlertRow,
  price: number,
  marketDate: string,
  triggeredOn: string | null,
): AlertUpdate | null {
  const threshold = thresholdPrice(alert);
  if (threshold === null || !(price > 0)) return null;
  const up = isUp(alert.condition);
  const met = up ? price >= threshold : price <= threshold;

  if (alert.repeat === "once") {
    return { id: alert.id, price, fire: met, rearm_ready: alert.rearm_ready, fired_on: marketDate };
  }

  let rearm = alert.rearm_ready;
  if (!rearm) {
    const back = up ? price < threshold * (1 - rearmBand) : price > threshold * (1 + rearmBand);
    if (back) rearm = true;
  }
  const firedToday = triggeredOn === marketDate;
  const fire = met && rearm && !firedToday;
  return { id: alert.id, price, fire, rearm_ready: fire ? false : rearm, fired_on: marketDate };
}

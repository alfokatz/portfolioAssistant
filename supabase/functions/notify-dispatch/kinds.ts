// Los tipos de notificación y las reglas de cada uno. Agregar un tipo:
// el check de `notification_outbox.kind`, una entrada acá y su plantilla en
// templates.ts.

export type Tier = "free" | "premium" | "gold";

export type Kind =
  | "test"
  | "price_alert"
  | "big_move"
  | "big_move_digest"
  | "portfolio_move"
  | "weekly_report"
  | "etoro_reconnect"
  | "earnings_tomorrow"
  | "earnings_result";

/// Preferencia del usuario que la controla (columna de
/// `notification_preferences`).
export type PrefKey =
  | "price_alerts"
  | "big_moves"
  | "portfolio_moves"
  | "weekly_report"
  | "earnings"
  | "service";

export type KindMeta = {
  pref: PrefKey | null;
  /// automatic: cuenta para el tope diario. requested: la pidió el usuario
  /// (alerta). service: algo de su cuenta que no puede esperar.
  category: "automatic" | "requested" | "service" | "test";
  minTier: Tier;
  /// Qué pasa si cae en el horario de silencio: `drop` (de mercado: a la
  /// mañana ya es viejo) o `defer` (se manda al terminar el silencio).
  quiet: "drop" | "defer" | "ignore";
  /// Pasado este tiempo desde que se generó, ya no se manda.
  maxAgeMinutes: number;
  /// Canal de Android (se crean en la app con estos ids).
  androidChannel: "price_alerts" | "portfolio" | "reports" | "account";
  /// iOS: `time-sensitive` atraviesa el modo concentración (solo lo que el
  /// usuario pidió).
  interruption: "time-sensitive" | "active";
};

export const kinds: Record<Kind, KindMeta> = {
  test: {
    pref: null,
    category: "test",
    minTier: "free",
    quiet: "ignore",
    maxAgeMinutes: 60,
    androidChannel: "account",
    interruption: "active",
  },
  price_alert: {
    pref: "price_alerts",
    category: "requested",
    minTier: "free", // el tope por plan lo controla la base (plan_limits)
    quiet: "defer",
    maxAgeMinutes: 24 * 60,
    androidChannel: "price_alerts",
    interruption: "time-sensitive",
  },
  big_move: {
    pref: "big_moves",
    category: "automatic",
    minTier: "free",
    quiet: "drop",
    maxAgeMinutes: 60,
    androidChannel: "portfolio",
    interruption: "active",
  },
  big_move_digest: {
    pref: "big_moves",
    category: "automatic",
    minTier: "free",
    quiet: "drop",
    maxAgeMinutes: 60,
    androidChannel: "portfolio",
    interruption: "active",
  },
  portfolio_move: {
    pref: "portfolio_moves",
    category: "automatic",
    minTier: "free",
    quiet: "drop",
    maxAgeMinutes: 60,
    androidChannel: "portfolio",
    interruption: "active",
  },
  weekly_report: {
    pref: "weekly_report",
    category: "automatic",
    minTier: "free",
    quiet: "defer",
    maxAgeMinutes: 2 * 24 * 60,
    androidChannel: "reports",
    interruption: "active",
  },
  etoro_reconnect: {
    pref: "service",
    category: "service",
    minTier: "free",
    quiet: "defer",
    maxAgeMinutes: 3 * 24 * 60,
    androidChannel: "account",
    interruption: "active",
  },
  earnings_tomorrow: {
    pref: "earnings",
    category: "automatic",
    minTier: "gold",
    quiet: "defer",
    maxAgeMinutes: 12 * 60,
    androidChannel: "reports",
    interruption: "active",
  },
  earnings_result: {
    pref: "earnings",
    category: "automatic",
    minTier: "gold",
    quiet: "defer",
    maxAgeMinutes: 24 * 60,
    androidChannel: "reports",
    interruption: "active",
  },
};

export function isKind(value: string): value is Kind {
  return Object.hasOwn(kinds, value);
}

const tierRank: Record<Tier, number> = { free: 0, premium: 1, gold: 2 };

export function tierAllows(tier: string, min: Tier): boolean {
  const rank = tierRank[tier as Tier] ?? 0;
  return rank >= tierRank[min];
}

/// Tope de notificaciones automáticas por usuario en 24 h.
export const dailyAutomaticCap = 3;

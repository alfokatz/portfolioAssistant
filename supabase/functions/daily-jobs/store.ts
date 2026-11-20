// Acceso a la base de daily-jobs (RPCs de 20261011030000_push_producers.sql).

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { AllocationInput, ContributionInput, HoldingWeights, LocalUser, OutboxInsert } from "./jobs.ts";

export interface JobsStore {
  usersAtLocalHour(hour: number): Promise<LocalUser[]>;
  /// Devuelve cuántas entraron (las repetidas no).
  enqueue(rows: OutboxInsert[]): Promise<number>;
  /// El interruptor del informe semanal (`app_config.weekly_report`).
  weeklyReportEnabled(): Promise<boolean>;
  /// Fuente de noticias/resultados (`app_config.news_provider`): "legacy"
  /// (Finnhub) o "v2" (SEC EDGAR). Sin implementar = legacy.
  newsProvider?(): Promise<string>;
  /// Planes de cartera con avisos prendidos (Premium/Gold) de [userIds].
  allocationInputs?(userIds: string[]): Promise<AllocationInput[]>;
  /// Peso de cada acción en la cartera de [userIds] (para el aviso de
  /// resultados de mañana).
  holdingWeights?(userIds: string[]): Promise<HoldingWeights>;
  /// Planes con recordatorio de aporte (Premium/Gold) de [userIds].
  contributionInputs?(userIds: string[]): Promise<ContributionInput[]>;
  purge(): Promise<void>;
}

function fail(what: string, error: { message: string } | null) {
  if (error) throw new Error(`${what}: ${error.message}`);
}

export function supabaseJobsStore(db: SupabaseClient): JobsStore {
  return {
    async usersAtLocalHour(hour) {
      const { data, error } = await db.rpc("push_users_at_local_hour", { p_hour: hour });
      fail("usersAtLocalHour", error);
      return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
        user_id: r.user_id as string,
        timezone: r.timezone as string,
        local_date: String(r.local_date),
        local_dow: Number(r.local_dow),
        tier: (r.tier as string) ?? "free",
        symbols: (r.symbols as string[]) ?? [],
      }));
    },
    async enqueue(rows) {
      const { data, error } = await db.rpc("push_enqueue", { p_rows: rows });
      fail("enqueue", error);
      return (data as number) ?? 0;
    },
    async weeklyReportEnabled() {
      const { data, error } = await db.from("app_config").select("value").eq("key", "weekly_report").maybeSingle();
      fail("weeklyReportEnabled", error);
      return (data?.value as { enabled?: boolean } | null)?.enabled === true;
    },
    async newsProvider() {
      const { data } = await db.from("app_config").select("value").eq("key", "news_provider").maybeSingle();
      return (data?.value as { provider?: string } | null)?.provider === "v2" ? "v2" : "legacy";
    },
    async allocationInputs(userIds) {
      const { data, error } = await db.rpc("allocation_drift_inputs", { p_user_ids: userIds });
      fail("allocationInputs", error);
      return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
        user_id: r.user_id as string,
        targets: (r.targets as Record<string, number>) ?? {},
        drift_threshold: Number(r.drift_threshold),
        holdings: ((r.holdings as Record<string, unknown>[]) ?? []).map((h) => ({
          symbol: String(h.symbol),
          quantity: Number(h.quantity),
          price: h.price === null || h.price === undefined ? null : Number(h.price),
        })),
      }));
    },
    async holdingWeights(userIds) {
      const { data, error } = await db.rpc("push_holding_weights", { p_user_ids: userIds });
      fail("holdingWeights", error);
      const out: HoldingWeights = new Map();
      for (const r of (data ?? []) as Record<string, unknown>[]) {
        const user = r.user_id as string;
        const map = out.get(user) ?? new Map<string, number>();
        if (r.weight_pct !== null && r.weight_pct !== undefined) map.set(String(r.symbol), Number(r.weight_pct));
        out.set(user, map);
      }
      return out;
    },
    async contributionInputs(userIds) {
      const { data, error } = await db.rpc("contribution_reminder_inputs", { p_user_ids: userIds });
      fail("contributionInputs", error);
      return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
        user_id: r.user_id as string,
        targets: (r.targets as Record<string, number>) ?? {},
        contribution_day: Number(r.contribution_day),
        contribution_amount: r.contribution_amount === null || r.contribution_amount === undefined
          ? null
          : Number(r.contribution_amount),
        holdings: ((r.holdings as Record<string, unknown>[]) ?? []).map((h) => ({
          symbol: String(h.symbol),
          quantity: Number(h.quantity),
          price: h.price === null || h.price === undefined ? null : Number(h.price),
        })),
      }));
    },
    async purge() {
      const { error } = await db.rpc("push_purge");
      fail("purge", error);
    },
  };
}

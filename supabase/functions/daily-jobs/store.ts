// Acceso a la base de daily-jobs (RPCs de 20261011030000_push_producers.sql).

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type {
  AllocationInput,
  BriefPushInput,
  CachedHeadline,
  ContributionInput,
  HoldingWeights,
  LocalUser,
  OutboxInsert,
} from "./jobs.ts";

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
  /// Brief diario (spec §3.7): insumos del push de [userIds]
  /// (`daily_brief_push_inputs`). Sin implementar = nadie lo tiene prendido.
  dailyBriefInputs?(userIds: string[]): Promise<BriefPushInput[]>;
  /// true si el interruptor `daily_brief` está prendido para alguien
  /// (`_daily_brief_cron_on`). Sin implementar = se asume prendido.
  dailyBriefCronOn?(): Promise<boolean>;
  /// Titulares ya calentados de [symbols] para la fecha local [day]: solo lee
  /// la caché (`gdelt:t:<SYM>:<día>`), nunca consulta GDELT.
  warmedHeadlines?(symbols: string[], day: string): Promise<Map<string, CachedHeadline[]>>;
  /// Hashes de las señales que el brief ya avisó en el mes [month] (`YYYY-MM`).
  seenBriefSignals?(userIds: string[], month: string): Promise<Map<string, Set<string>>>;
  purge(): Promise<void>;
  /// 04:00 UTC: videos de más de 7 días y briefs de más de 14
  /// (`daily_brief_purge`).
  purgeBrief?(): Promise<void>;
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
    async dailyBriefCronOn() {
      const { data, error } = await db.rpc("_daily_brief_cron_on");
      fail("dailyBriefCronOn", error);
      return data === true;
    },
    async dailyBriefInputs(userIds) {
      const { data, error } = await db.rpc("daily_brief_push_inputs", { p_user_ids: userIds });
      fail("dailyBriefInputs", error);
      return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
        user_id: r.user_id as string,
        tier: (r.tier as string) ?? "free",
        big_move_sensitivity: (r.big_move_sensitivity as string) ?? "normal",
        brief_on: r.brief_on === true,
        push_piece: r.push_piece === true,
        show_amounts: r.show_amounts === true,
        last_brief_day: r.last_brief_day ? String(r.last_brief_day) : null,
        holdings: ((r.holdings as Record<string, unknown>[]) ?? []).map((h) => ({
          symbol: String(h.symbol),
          weight_pct: h.weight_pct === null || h.weight_pct === undefined ? null : Number(h.weight_pct),
        })),
      }));
    },
    async warmedHeadlines(symbols, day) {
      const out = new Map<string, CachedHeadline[]>();
      for (let i = 0; i < symbols.length; i += 100) {
        const chunk = symbols.slice(i, i + 100);
        const { data, error } = await db.from("data_source_cache").select("cache_key, body")
          .in("cache_key", chunk.map((s) => `gdelt:t:${s}:${day}`));
        fail("warmedHeadlines", error);
        for (const row of (data ?? []) as { cache_key: string; body: { items?: CachedHeadline[] } }[]) {
          const symbol = row.cache_key.slice("gdelt:t:".length, row.cache_key.length - day.length - 1);
          out.set(symbol, (row.body?.items ?? []).map((h) => ({ title: String(h.title), published_at: String(h.published_at) })));
        }
      }
      return out;
    },
    async seenBriefSignals(userIds, month) {
      const out = new Map<string, Set<string>>();
      const { data, error } = await db.from("notification_outbox").select("user_id, data")
        .eq("kind", "daily_brief").in("user_id", userIds).like("dedupe_key", `daily_brief:${month}-%`);
      fail("seenBriefSignals", error);
      for (const row of (data ?? []) as { user_id: string; data: { signal_keys?: unknown } }[]) {
        const set = out.get(row.user_id) ?? new Set<string>();
        for (const k of Array.isArray(row.data?.signal_keys) ? row.data.signal_keys : []) set.add(String(k));
        out.set(row.user_id, set);
      }
      return out;
    },
    async purge() {
      const { error } = await db.rpc("push_purge");
      fail("purge", error);
    },
    async purgeBrief() {
      const { error } = await db.rpc("daily_brief_purge");
      fail("purgeBrief", error);
    },
  };
}

// Acceso a la base de daily-jobs (RPCs de 20261011030000_push_producers.sql).

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { LocalUser, OutboxInsert } from "./jobs.ts";

export interface JobsStore {
  usersAtLocalHour(hour: number): Promise<LocalUser[]>;
  /// Devuelve cuántas entraron (las repetidas no).
  enqueue(rows: OutboxInsert[]): Promise<number>;
  /// El interruptor del informe semanal (`app_config.weekly_report`).
  weeklyReportEnabled(): Promise<boolean>;
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
    async purge() {
      const { error } = await db.rpc("push_purge");
      fail("purge", error);
    },
  };
}

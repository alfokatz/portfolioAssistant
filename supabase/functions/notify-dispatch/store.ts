// Acceso a la base de notify-dispatch (RPCs de
// 20261011000000_push_notifications.sql). Interfaz para que los tests usen
// un store en memoria.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export type OutboxRow = {
  id: number;
  user_id: string;
  kind: string;
  dedupe_key: string;
  data: Record<string, unknown>;
  created_at: string;
  attempts: number;
};

export type Device = {
  id: string;
  token: string;
  platform: "ios" | "android";
  locale: "es" | "en";
  timezone: string;
};

export type Prefs = {
  enabled: boolean;
  price_alerts: boolean;
  big_moves: boolean;
  portfolio_moves: boolean;
  weekly_report: boolean;
  earnings: boolean;
  service: boolean;
  big_move_sensitivity: "low" | "normal" | "high";
  quiet_start: string;
  quiet_end: string;
  show_amounts: boolean;
};

export type UserContext = {
  tier: string;
  prefs: Prefs;
  /// Del más reciente al más viejo (la zona del primero manda).
  devices: Device[];
  automaticLast24h: number;
};

export type PushConfig = {
  enabled: boolean;
  allowUsers: string[];
  kinds: Record<string, boolean>;
};

export interface DispatchStore {
  config(): Promise<PushConfig>;
  claim(limit: number): Promise<OutboxRow[]>;
  contexts(userIds: string[]): Promise<Map<string, UserContext>>;
  /// No se manda: `skipped`, o `pending` otra vez desde [notBefore].
  finish(id: number, status: "skipped" | "pending", reason: string, notBefore?: number): Promise<void>;
  beginLog(outboxId: number): Promise<number>;
  complete(outboxId: number, logId: number, deviceCount: number): Promise<void>;
  deleteDevices(ids: string[]): Promise<void>;
}

export function readPushConfig(value: unknown): PushConfig {
  const v = (value ?? {}) as Record<string, unknown>;
  return {
    enabled: v.enabled === true,
    allowUsers: Array.isArray(v.allow_users) ? v.allow_users.map(String) : [],
    kinds: typeof v.kinds === "object" && v.kinds !== null ? v.kinds as Record<string, boolean> : {},
  };
}

function fail(what: string, error: { message: string } | null) {
  if (error) throw new Error(`${what}: ${error.message}`);
}

export function supabaseDispatchStore(db: SupabaseClient): DispatchStore {
  return {
    async config() {
      const { data, error } = await db.from("app_config").select("value").eq("key", "push").maybeSingle();
      fail("config", error);
      return readPushConfig(data?.value);
    },
    async claim(limit) {
      const { data, error } = await db.rpc("push_claim_outbox", { p_limit: limit });
      fail("claim", error);
      return (data ?? []) as OutboxRow[];
    },
    async contexts(userIds) {
      const out = new Map<string, UserContext>();
      if (userIds.length === 0) return out;
      const { data, error } = await db.rpc("push_dispatch_context", { p_user_ids: userIds });
      fail("contexts", error);
      for (const r of (data ?? []) as Record<string, unknown>[]) {
        out.set(r.user_id as string, {
          tier: (r.tier as string) ?? "free",
          prefs: r.prefs as Prefs,
          devices: (r.devices as Device[]) ?? [],
          automaticLast24h: (r.automatic_last_24h as number) ?? 0,
        });
      }
      return out;
    },
    async finish(id, status, reason, notBefore) {
      const { error } = await db.rpc("push_finish_outbox", {
        p_id: id,
        p_status: status,
        p_skip_reason: reason,
        p_not_before: notBefore ? new Date(notBefore).toISOString() : null,
      });
      fail("finish", error);
    },
    async beginLog(outboxId) {
      const { data, error } = await db.rpc("push_begin_log", { p_outbox_id: outboxId });
      fail("beginLog", error);
      return data as number;
    },
    async complete(outboxId, logId, deviceCount) {
      const { error } = await db.rpc("push_complete", {
        p_outbox_id: outboxId,
        p_log_id: logId,
        p_device_count: deviceCount,
      });
      fail("complete", error);
    },
    async deleteDevices(ids) {
      if (ids.length === 0) return;
      const { error } = await db.from("push_devices").delete().in("id", ids);
      fail("deleteDevices", error);
    },
  };
}

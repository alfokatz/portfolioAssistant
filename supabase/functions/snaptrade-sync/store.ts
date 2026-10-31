// Acceso a la base de snaptrade-sync (RPCs de 20261031000000_snaptrade_sync.sql).
// Interfaz para que los tests usen una en memoria.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { BrokerageSummary } from "./mapping.ts";
import type { SnaptradeUser } from "./snaptrade.ts";

export type ConnectionStatus = "pending" | "connected" | "reconnect_required" | "disconnected";

export type SnaptradeConnection = {
  status: ConnectionStatus;
  lastSyncAt: string | null;
  lastResult: Record<string, unknown> | null;
};

export type PositionRow = {
  id: string;
  external_id: string;
  ticker: string;
  quantity: number;
  purchase_price: number;
  purchase_date: string;
  broker_price: number;
};

export interface SnaptradeStore {
  effectiveTier(userId: string): Promise<string>;
  rateLimitHit(userId: string, perMinute: number): Promise<boolean>;
  getConnection(userId: string): Promise<SnaptradeConnection | null>;
  /// Crea la fila, o la vuelve a `pending` si estaba desconectada o si
  /// [reset] (usuario de SnapTrade nuevo).
  upsertPending(userId: string, reset: boolean): Promise<void>;
  saveUser(userId: string, user: SnaptradeUser): Promise<void>;
  readUser(userId: string): Promise<SnaptradeUser | null>;
  deleteUser(userId: string): Promise<void>;
  tryLock(userId: string, seconds: number): Promise<boolean>;
  unlock(userId: string): Promise<void>;
  takeRefresh(userId: string, perDay: number): Promise<boolean>;
  applySync(
    userId: string,
    positions: PositionRow[],
    brokerages: BrokerageSummary[],
    result: Record<string, unknown>,
  ): Promise<void>;
  markError(userId: string, type: string, reconnect: boolean): Promise<void>;
  disconnect(userId: string, keepAsManual: boolean): Promise<{ open: number }>;
}

function fail(what: string, error: { message: string } | null) {
  if (error) throw new Error(`${what}: ${error.message}`);
}

export function supabaseStore(db: SupabaseClient): SnaptradeStore {
  return {
    async effectiveTier(userId) {
      const { data, error } = await db.rpc("_effective_tier", { p_user_id: userId });
      fail("effectiveTier", error);
      return (data as string | null) ?? "free";
    },
    async rateLimitHit(userId, perMinute) {
      const { data, error } = await db.rpc("rate_limit_hit", {
        p_user_id: userId,
        p_bucket: "snaptrade_sync",
        p_per_minute: perMinute,
      });
      fail("rateLimitHit", error);
      return data === true;
    },
    async getConnection(userId) {
      const { data, error } = await db
        .from("snaptrade_connections")
        .select("status, last_sync_at, last_result")
        .eq("user_id", userId)
        .maybeSingle();
      fail("getConnection", error);
      if (!data) return null;
      return {
        status: data.status as ConnectionStatus,
        lastSyncAt: data.last_sync_at as string | null,
        lastResult: data.last_result as Record<string, unknown> | null,
      };
    },
    async upsertPending(userId, reset) {
      const current = await this.getConnection(userId);
      if (current && current.status !== "disconnected" && !reset) return;
      const { error } = await db.from("snaptrade_connections").upsert({
        user_id: userId,
        status: "pending",
        brokerages: [],
        last_error_type: null,
        updated_at: new Date().toISOString(),
      });
      fail("upsertPending", error);
    },
    async saveUser(userId, user) {
      const { error } = await db.rpc("snaptrade_secret_save", {
        p_user_id: userId,
        p_payload: JSON.stringify({ user_id: user.userId, user_secret: user.userSecret }),
      });
      fail("saveUser", error);
    },
    async readUser(userId) {
      const { data, error } = await db.rpc("snaptrade_secret_read", { p_user_id: userId });
      fail("readUser", error);
      if (typeof data !== "string") return null;
      const parsed = JSON.parse(data);
      return { userId: parsed.user_id, userSecret: parsed.user_secret };
    },
    async deleteUser(userId) {
      const { error } = await db.rpc("snaptrade_secret_delete", { p_user_id: userId });
      fail("deleteUser", error);
    },
    async tryLock(userId, seconds) {
      const { data, error } = await db.rpc("snaptrade_try_lock", { p_user_id: userId, p_seconds: seconds });
      fail("tryLock", error);
      return data === true;
    },
    async unlock(userId) {
      const { error } = await db.rpc("snaptrade_unlock", { p_user_id: userId });
      fail("unlock", error);
    },
    async takeRefresh(userId, perDay) {
      const { data, error } = await db.rpc("snaptrade_take_refresh", { p_user_id: userId, p_per_day: perDay });
      fail("takeRefresh", error);
      return data === true;
    },
    async applySync(userId, positions, brokerages, result) {
      const { error } = await db.rpc("snaptrade_apply_sync", {
        p_user_id: userId,
        p_positions: positions,
        p_brokerages: brokerages,
        p_result: result,
      });
      fail("applySync", error);
    },
    async markError(userId, type, reconnect) {
      const { error } = await db.from("snaptrade_connections").update({
        last_sync_status: "error",
        last_error_type: type,
        ...(reconnect ? { status: "reconnect_required" } : {}),
        updated_at: new Date().toISOString(),
      }).eq("user_id", userId);
      fail("markError", error);
    },
    async disconnect(userId, keepAsManual) {
      const { data, error } = await db.rpc("snaptrade_disconnect", {
        p_user_id: userId,
        p_keep_as_manual: keepAsManual,
      });
      fail("disconnect", error);
      return { open: Number((data as { open?: number })?.open ?? 0) };
    },
  };
}

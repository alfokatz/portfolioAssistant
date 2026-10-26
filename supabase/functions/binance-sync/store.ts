// Acceso a la base de binance-sync (RPCs de 20261016000400_binance_sync.sql).
// Interfaz para que los tests usen una en memoria.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { BinanceKeys } from "./binance.ts";

export type ConnectionStatus = "connected" | "reconnect_required" | "disconnected";

export type BinanceConnection = {
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

export interface BinanceStore {
  effectiveTier(userId: string): Promise<string>;
  rateLimitHit(userId: string, perMinute: number): Promise<boolean>;
  getConnection(userId: string): Promise<BinanceConnection | null>;
  upsertConnected(userId: string, keyHint: string): Promise<void>;
  saveKeys(userId: string, keys: BinanceKeys): Promise<void>;
  readKeys(userId: string): Promise<BinanceKeys | null>;
  tryLock(userId: string, seconds: number): Promise<boolean>;
  unlock(userId: string): Promise<void>;
  applySync(userId: string, positions: PositionRow[], result: Record<string, unknown>): Promise<void>;
  markError(userId: string, type: string, reconnect: boolean): Promise<void>;
  disconnect(userId: string, keepAsManual: boolean): Promise<{ open: number }>;
}

function fail(what: string, error: { message: string } | null) {
  if (error) throw new Error(`${what}: ${error.message}`);
}

export function supabaseStore(db: SupabaseClient): BinanceStore {
  return {
    async effectiveTier(userId) {
      const { data, error } = await db.rpc("_effective_tier", { p_user_id: userId });
      fail("effectiveTier", error);
      return (data as string | null) ?? "free";
    },
    async rateLimitHit(userId, perMinute) {
      const { data, error } = await db.rpc("rate_limit_hit", {
        p_user_id: userId,
        p_bucket: "binance_sync",
        p_per_minute: perMinute,
      });
      fail("rateLimitHit", error);
      return data === true;
    },
    async getConnection(userId) {
      const { data, error } = await db
        .from("binance_connections")
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
    async upsertConnected(userId, keyHint) {
      const { error } = await db.from("binance_connections").upsert({
        user_id: userId,
        status: "connected",
        api_key_hint: keyHint,
        connected_at: new Date().toISOString(),
        last_error_type: null,
        updated_at: new Date().toISOString(),
      });
      fail("upsertConnected", error);
    },
    async saveKeys(userId, keys) {
      const { error } = await db.rpc("binance_keys_save", {
        p_user_id: userId,
        p_payload: JSON.stringify({ api_key: keys.apiKey, api_secret: keys.apiSecret }),
      });
      fail("saveKeys", error);
    },
    async readKeys(userId) {
      const { data, error } = await db.rpc("binance_keys_read", { p_user_id: userId });
      fail("readKeys", error);
      if (typeof data !== "string") return null;
      const parsed = JSON.parse(data);
      return { apiKey: parsed.api_key, apiSecret: parsed.api_secret };
    },
    async tryLock(userId, seconds) {
      const { data, error } = await db.rpc("binance_try_lock", { p_user_id: userId, p_seconds: seconds });
      fail("tryLock", error);
      return data === true;
    },
    async unlock(userId) {
      const { error } = await db.rpc("binance_unlock", { p_user_id: userId });
      fail("unlock", error);
    },
    async applySync(userId, positions, result) {
      const { error } = await db.rpc("binance_apply_sync", {
        p_user_id: userId,
        p_positions: positions,
        p_result: result,
      });
      fail("applySync", error);
    },
    async markError(userId, type, reconnect) {
      const { error } = await db.from("binance_connections").update({
        last_sync_status: "error",
        last_error_type: type,
        ...(reconnect ? { status: "reconnect_required" } : {}),
        updated_at: new Date().toISOString(),
      }).eq("user_id", userId);
      fail("markError", error);
    },
    async disconnect(userId, keepAsManual) {
      const { data, error } = await db.rpc("binance_disconnect", {
        p_user_id: userId,
        p_keep_as_manual: keepAsManual,
      });
      fail("disconnect", error);
      return { open: Number((data as { open?: number })?.open ?? 0) };
    },
  };
}

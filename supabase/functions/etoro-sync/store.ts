// Persistencia de etoro-sync detrás de una interfaz, así los tests de la
// lógica corren sin base (store en memoria) y la implementación real usa las
// tablas y RPCs de 20261009000000_etoro_sync.sql con la service role.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { EtoroTokens } from "./etoro.ts";
import type { InstrumentMeta, PortyClosedRow, PortyOpenRow } from "./mapping.ts";

export type ConnectionStatus = "connected" | "reconnect_required" | "disconnected";

export type Connection = {
  userId: string;
  etoroSub: string | null;
  status: ConnectionStatus;
  grantedScopes: string[];
  lastSyncAt: string | null;
  lastResult: SyncResult | null;
  historySyncedUntil: string | null;
};

export type OAuthState = {
  state: string;
  userId: string;
  codeVerifier: string;
  nonce: string;
  createdAt: string;
};

export type SyncResult = {
  imported: number;
  closedImported: number;
  notImported: { ticker: string; name: string | null; reason: string; count: number }[];
  closedNotImported: { ticker: string; name: string | null; reason: string; count: number }[];
  possibleDuplicates: string[];
  syncedAt: string;
};

export type ApplySync = {
  open: (PortyOpenRow & { id: string })[];
  closed: (PortyClosedRow & { id: string })[];
  result: SyncResult;
  historyUntil: string;
};

export interface EtoroStore {
  effectiveTier(userId: string): Promise<string>;
  rateLimitHit(userId: string, perMinute: number): Promise<boolean>;

  saveOAuthState(s: OAuthState): Promise<void>;
  /// Lee y BORRA el state (un solo uso). null si no existe.
  takeOAuthState(state: string): Promise<OAuthState | null>;

  getConnection(userId: string): Promise<Connection | null>;
  upsertConnected(userId: string, etoroSub: string, scopes: string[]): Promise<void>;
  markReconnectRequired(userId: string): Promise<void>;
  markSyncError(userId: string, errorType: string): Promise<void>;

  saveTokens(userId: string, tokens: EtoroTokens): Promise<void>;
  readTokens(userId: string): Promise<EtoroTokens | null>;

  tryLock(userId: string, seconds: number): Promise<boolean>;
  unlock(userId: string): Promise<void>;

  getInstruments(ids: number[]): Promise<Map<number, InstrumentMeta>>;
  saveInstruments(items: InstrumentMeta[]): Promise<void>;

  manualOpenTickers(userId: string): Promise<string[]>;
  applySync(userId: string, data: ApplySync): Promise<void>;
  disconnect(userId: string, keepAsManual: boolean): Promise<{ open: number; closed: number }>;
}

function fail(what: string, error: { message: string } | null): void {
  // Sin datos del usuario en el mensaje: solo qué operación falló.
  if (error) throw new Error(`store.${what}: ${error.message}`);
}

export function supabaseStore(db: SupabaseClient): EtoroStore {
  return {
    async effectiveTier(userId) {
      const { data, error } = await db.rpc("_effective_tier", { p_user_id: userId });
      fail("effectiveTier", error);
      return (data as string | null) ?? "free";
    },

    async rateLimitHit(userId, perMinute) {
      const { data, error } = await db.rpc("rate_limit_hit", {
        p_user_id: userId,
        p_bucket: "etoro",
        p_per_minute: perMinute,
      });
      fail("rateLimitHit", error);
      return data !== false;
    },

    async saveOAuthState(s) {
      const { error } = await db.from("etoro_oauth_states").insert({
        state: s.state,
        user_id: s.userId,
        code_verifier: s.codeVerifier,
        nonce: s.nonce,
        created_at: s.createdAt,
      });
      fail("saveOAuthState", error);
    },

    async takeOAuthState(state) {
      const { data, error } = await db
        .from("etoro_oauth_states")
        .delete()
        .eq("state", state)
        .select("state, user_id, code_verifier, nonce, created_at")
        .maybeSingle();
      fail("takeOAuthState", error);
      if (!data) return null;
      return {
        state: data.state,
        userId: data.user_id,
        codeVerifier: data.code_verifier,
        nonce: data.nonce,
        createdAt: data.created_at,
      };
    },

    async getConnection(userId) {
      const { data, error } = await db
        .from("etoro_connections")
        .select("user_id, etoro_sub, status, granted_scopes, last_sync_at, last_result, history_synced_until")
        .eq("user_id", userId)
        .maybeSingle();
      fail("getConnection", error);
      if (!data) return null;
      return {
        userId: data.user_id,
        etoroSub: data.etoro_sub,
        status: data.status,
        grantedScopes: data.granted_scopes ?? [],
        lastSyncAt: data.last_sync_at,
        lastResult: data.last_result,
        historySyncedUntil: data.history_synced_until,
      };
    },

    async upsertConnected(userId, etoroSub, scopes) {
      const now = new Date().toISOString();
      const { error } = await db.from("etoro_connections").upsert({
        user_id: userId,
        etoro_sub: etoroSub,
        status: "connected",
        granted_scopes: scopes,
        connected_at: now,
        last_error_type: null,
        updated_at: now,
      });
      fail("upsertConnected", error);
    },

    async markReconnectRequired(userId) {
      const { error } = await db
        .from("etoro_connections")
        .update({
          status: "reconnect_required",
          last_sync_status: "error",
          last_error_type: "reconnect_required",
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", userId);
      fail("markReconnectRequired", error);
    },

    async markSyncError(userId, errorType) {
      const { error } = await db
        .from("etoro_connections")
        .update({
          last_sync_status: "error",
          last_error_type: errorType,
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", userId);
      fail("markSyncError", error);
    },

    async saveTokens(userId, tokens) {
      const { error } = await db.rpc("etoro_tokens_save", {
        p_user_id: userId,
        p_payload: JSON.stringify(tokens),
      });
      fail("saveTokens", error);
    },

    async readTokens(userId) {
      const { data, error } = await db.rpc("etoro_tokens_read", { p_user_id: userId });
      fail("readTokens", error);
      if (typeof data !== "string" || data === "") return null;
      return JSON.parse(data) as EtoroTokens;
    },

    async tryLock(userId, seconds) {
      const { data, error } = await db.rpc("etoro_try_lock", { p_user_id: userId, p_seconds: seconds });
      fail("tryLock", error);
      return data === true;
    },

    async unlock(userId) {
      const { error } = await db.rpc("etoro_unlock", { p_user_id: userId });
      fail("unlock", error);
    },

    async getInstruments(ids) {
      const out = new Map<number, InstrumentMeta>();
      if (ids.length === 0) return out;
      const { data, error } = await db
        .from("etoro_instruments")
        .select("instrument_id, symbol_full, display_name, instrument_type, exchange, updated_at")
        .in("instrument_id", ids);
      fail("getInstruments", error);
      const maxAgeMs = 24 * 60 * 60 * 1000;
      for (const row of data ?? []) {
        if (Date.now() - Date.parse(row.updated_at) > maxAgeMs) continue;
        out.set(row.instrument_id, {
          instrumentId: row.instrument_id,
          symbolFull: row.symbol_full,
          displayName: row.display_name,
          instrumentType: row.instrument_type,
          exchange: row.exchange,
        });
      }
      return out;
    },

    async saveInstruments(items) {
      if (items.length === 0) return;
      const now = new Date().toISOString();
      const { error } = await db.from("etoro_instruments").upsert(
        items.map((i) => ({
          instrument_id: i.instrumentId,
          symbol_full: i.symbolFull,
          display_name: i.displayName ?? null,
          instrument_type: i.instrumentType ?? null,
          exchange: i.exchange ?? null,
          updated_at: now,
        })),
      );
      fail("saveInstruments", error);
    },

    async manualOpenTickers(userId) {
      const { data, error } = await db
        .from("positions")
        .select("ticker")
        .eq("user_id", userId)
        .eq("source", "manual");
      fail("manualOpenTickers", error);
      return (data ?? []).map((r) => r.ticker as string);
    },

    async applySync(userId, d) {
      const { error } = await db.rpc("etoro_apply_sync", {
        p_user_id: userId,
        p_positions: d.open.map((r) => ({
          id: r.id,
          external_id: r.externalId,
          ticker: r.ticker,
          quantity: r.quantity,
          purchase_price: r.purchasePrice,
          purchase_date: r.purchaseDate,
        })),
        p_closed: d.closed.map((r) => ({
          id: r.id,
          external_id: r.externalId,
          ticker: r.ticker,
          quantity: r.quantity,
          avg_purchase_price: r.avgPurchasePrice,
          close_price: r.closePrice,
          close_date: r.closeDate,
          realized_pnl: r.realizedPnl,
        })),
        p_result: d.result,
        // eToro informa todo en USD para las acciones de EE.UU. que se
        // importan; la moneda de la cuenta no se pide (requiere otro scope).
        p_account_currency: null,
        p_history_until: d.historyUntil,
      });
      fail("applySync", error);
    },

    async disconnect(userId, keepAsManual) {
      const { data, error } = await db.rpc("etoro_disconnect", {
        p_user_id: userId,
        p_keep_as_manual: keepAsManual,
      });
      fail("disconnect", error);
      return { open: data?.open ?? 0, closed: data?.closed ?? 0 };
    },
  };
}

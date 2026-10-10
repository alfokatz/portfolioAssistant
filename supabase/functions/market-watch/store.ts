// Acceso a la base de market-watch. Interfaz para los tests.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { AlertRow, AlertUpdate } from "./alerts.ts";
import type { Holding, UserMoves } from "./moves.ts";
import type { Quote } from "./quotes.ts";

export interface MarketStore {
  activeAlerts(): Promise<AlertRow[]>;
  /// Posiciones abiertas (sumadas por ticker) de quien quiere movimientos
  /// fuertes o de la cartera y tiene al menos un dispositivo.
  holdings(): Promise<Holding[]>;
  saveQuotes(quotes: Quote[], fetchedAt: number): Promise<void>;
  /// Devuelve cuántas se dispararon.
  recordAlerts(updates: AlertUpdate[]): Promise<number>;
  /// Devuelve cuántas notificaciones quedaron pendientes en el outbox.
  enqueueMoves(marketDate: string, items: UserMoves[]): Promise<number>;
}

function fail(what: string, error: { message: string } | null) {
  if (error) throw new Error(`${what}: ${error.message}`);
}

export function supabaseMarketStore(db: SupabaseClient): MarketStore {
  return {
    async activeAlerts() {
      const { data, error } = await db
        .from("price_alerts")
        .select("id, user_id, symbol, condition, target, reference_price, repeat, rearm_ready, triggered_at")
        .eq("status", "active");
      fail("activeAlerts", error);
      return (data ?? []).map((r) => ({
        ...r,
        target: Number(r.target),
        reference_price: r.reference_price === null ? null : Number(r.reference_price),
      })) as AlertRow[];
    },
    async holdings() {
      const { data, error } = await db.rpc("market_watch_holdings");
      fail("holdings", error);
      return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
        user_id: r.user_id as string,
        symbol: r.symbol as string,
        quantity: Number(r.quantity),
        sensitivity: (r.sensitivity as Holding["sensitivity"]) ?? "normal",
        big_moves: r.big_moves === true,
        portfolio_moves: r.portfolio_moves === true,
      }));
    },
    async saveQuotes(quotes, fetchedAt) {
      if (quotes.length === 0) return;
      const { error } = await db.from("market_quotes").upsert(
        quotes.map((q) => ({
          symbol: q.symbol,
          price: q.price,
          prev_close: q.prevClose,
          change_pct: q.changePct,
          currency: q.currency,
          market_state: q.marketState,
          quote_type: q.quoteType,
          fetched_at: new Date(fetchedAt).toISOString(),
        })),
      );
      fail("saveQuotes", error);
    },
    async recordAlerts(updates) {
      if (updates.length === 0) return 0;
      const { data, error } = await db.rpc("price_alerts_record", { p_rows: updates });
      fail("recordAlerts", error);
      return (data as number) ?? 0;
    },
    async enqueueMoves(marketDate, items) {
      if (items.length === 0) return 0;
      const { data, error } = await db.rpc("market_enqueue_moves", {
        p_market_date: marketDate,
        p_items: items,
      });
      fail("enqueueMoves", error);
      return (data as number) ?? 0;
    },
  };
}

// market-watch: cada 5 minutos con el mercado de EE.UU. abierto (pg_cron).
// 1. Cotiza en lote los símbolos de las alertas activas y de las carteras
//    de quien quiere movimientos fuertes.
// 2. Evalúa las alertas (F2) y los movimientos fuertes (F4).
// 3. Si algo quedó en el outbox, lo despacha en la misma corrida.
//
// POST /functions/v1/market-watch con `x-cron-secret`. Body opcional
// `{"force": true}` para probar fuera de horario.

import { corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { isCronRequest } from "../_shared/cron.ts";
import { runDispatch } from "../notify-dispatch/dispatch.ts";
import type { PushSender } from "../notify-dispatch/fcm.ts";
import type { DispatchStore } from "../notify-dispatch/store.ts";
import { evaluateAlert } from "./alerts.ts";
import { marketDate, marketPhase } from "./market_clock.ts";
import { benchmarkSymbol, computeMoves } from "./moves.ts";
import { fetchQuotes } from "./quotes.ts";
import type { MarketStore } from "./store.ts";

export type MarketDeps = Pick<Deps, "env" | "now" | "fetch"> & {
  store: MarketStore;
  dispatchStore: DispatchStore;
  sender: PushSender | null;
};

export type MarketSummary = {
  phase: string;
  symbols: number;
  quotes: number;
  alertsChecked: number;
  alertsFired: number;
  movesUsers: number;
  movesQueued: number;
  dispatched: number;
  skipped?: string;
};

export async function handle(req: Request, deps: MarketDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");
  if (!isCronRequest(req, deps)) return typedError(401, "unauthorized", "Missing or invalid cron secret");

  let force = false;
  try {
    force = (await req.json())?.force === true;
  } catch {
    // sin body
  }
  const summary = await runMarketWatch(deps, { force });
  console.log(JSON.stringify({ fn: "market-watch", ...summary }));
  return json(200, summary);
}

export async function runMarketWatch(deps: MarketDeps, opts: { force?: boolean } = {}): Promise<MarketSummary> {
  const now = deps.now();
  const phase = marketPhase(now);
  const summary: MarketSummary = {
    phase,
    symbols: 0,
    quotes: 0,
    alertsChecked: 0,
    alertsFired: 0,
    movesUsers: 0,
    movesQueued: 0,
    dispatched: 0,
  };
  if (phase === "closed" && !opts.force) return { ...summary, skipped: "market_closed" };

  const alerts = await deps.store.activeAlerts();
  // Los movimientos, recién 30 minutos después de la apertura.
  const watchMoves = phase === "open" || opts.force === true;
  const holdings = watchMoves ? await deps.store.holdings() : [];

  const alertSymbols = new Set(alerts.map((a) => a.symbol));
  const symbols = [...new Set([...alertSymbols, ...holdings.map((h) => h.symbol)])];
  if (holdings.length > 0) symbols.push(benchmarkSymbol);
  summary.symbols = symbols.length;
  if (symbols.length === 0) return summary;

  const quotes = await fetchQuotes(deps, symbols, alertSymbols);
  summary.quotes = quotes.size;
  await deps.store.saveQuotes([...quotes.values()], now);

  // ── Alertas ──
  const date = marketDate(now);
  const updates = [];
  for (const a of alerts) {
    const q = quotes.get(a.symbol);
    if (!q) continue;
    const triggeredOn = a.triggered_at ? marketDate(Date.parse(a.triggered_at)) : null;
    const u = evaluateAlert(a, q.price, date, triggeredOn);
    if (u) updates.push(u);
  }
  summary.alertsChecked = updates.length;
  summary.alertsFired = await deps.store.recordAlerts(updates);

  // ── Movimientos fuertes ──
  // Feriado: Yahoo no está en REGULAR y la variación es la del último día.
  const regular = [...quotes.values()].some((q) => q.marketState === "REGULAR");
  if (watchMoves && (regular || opts.force)) {
    const moves = computeMoves(holdings, quotes);
    summary.movesUsers = moves.length;
    summary.movesQueued = await deps.store.enqueueMoves(date, moves);
  }

  if ((summary.alertsFired > 0 || summary.movesQueued > 0) && deps.sender) {
    const d = await runDispatch(deps.dispatchStore, deps.sender, deps.now);
    summary.dispatched = d.sent;
  }
  return summary;
}

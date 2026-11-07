// El despacho: toma lo pendiente del outbox, decide si cada cosa se manda
// (interruptor, preferencias, plan, antigüedad, silencio, tope diario) y la
// manda a todos los dispositivos del usuario.

import type { PushSender } from "./fcm.ts";
import { dailyAutomaticCap, isKind, kinds, tierAllows } from "./kinds.ts";
import { quietEndsAt } from "./quiet.ts";
import type { DispatchStore, OutboxRow, PushConfig, UserContext } from "./store.ts";
import { type Locale, render } from "./templates.ts";

export type Decision =
  | { action: "send" }
  | { action: "skip"; reason: string }
  | { action: "defer"; reason: string; until: number };

/// Regla pura: ¿se manda esta fila ahora? [sentThisRun] = automáticas que
/// ya salieron para este usuario en esta corrida.
export function decide(
  row: OutboxRow,
  ctx: UserContext | undefined,
  config: PushConfig,
  nowMs: number,
  sentThisRun = 0,
): Decision {
  if (!isKind(row.kind)) return { action: "skip", reason: "unknown_kind" };
  const meta = kinds[row.kind];
  if (!config.enabled && !config.allowUsers.includes(row.user_id)) {
    return { action: "skip", reason: "push_disabled" };
  }
  if (config.kinds[row.kind] === false) return { action: "skip", reason: "kind_disabled" };
  if (!ctx || ctx.devices.length === 0) return { action: "skip", reason: "no_devices" };
  if (meta.category !== "test") {
    if (!ctx.prefs.enabled) return { action: "skip", reason: "user_disabled" };
    if (meta.pref && ctx.prefs[meta.pref] === false) return { action: "skip", reason: "user_disabled_kind" };
  }
  if (!tierAllows(ctx.tier, meta.minTier)) return { action: "skip", reason: "plan" };
  if (nowMs - Date.parse(row.created_at) > meta.maxAgeMinutes * 60_000) {
    return { action: "skip", reason: "stale" };
  }
  if (meta.quiet !== "ignore") {
    const until = quietEndsAt(nowMs, ctx.devices[0].timezone, ctx.prefs.quiet_start, ctx.prefs.quiet_end);
    if (until !== null) {
      // Si al terminar el silencio ya es vieja, no tiene sentido esperar.
      const stillFresh = until - Date.parse(row.created_at) <= meta.maxAgeMinutes * 60_000;
      return meta.quiet === "defer" && stillFresh
        ? { action: "defer", reason: "quiet_hours", until }
        : { action: "skip", reason: "quiet_hours" };
    }
  }
  if (meta.category === "automatic" && ctx.automaticLast24h + sentThisRun >= dailyAutomaticCap) {
    return { action: "skip", reason: "daily_cap" };
  }
  return { action: "send" };
}

export type DispatchSummary = {
  claimed: number;
  sent: number;
  skipped: Record<string, number>;
  deferred: number;
  failed: number;
  invalidTokens: number;
};

/// Prioridad dentro de una corrida: lo que pidió el usuario y lo de su
/// cuenta antes que lo automático (así el tope diario nunca se come una
/// alerta).
const categoryOrder = { requested: 0, service: 1, test: 2, automatic: 3 } as const;

export async function runDispatch(
  store: DispatchStore,
  sender: PushSender,
  now: () => number,
  opts: { limit?: number; concurrency?: number } = {},
): Promise<DispatchSummary> {
  const summary: DispatchSummary = {
    claimed: 0,
    sent: 0,
    skipped: {},
    deferred: 0,
    failed: 0,
    invalidTokens: 0,
  };
  const rows = await store.claim(opts.limit ?? 500);
  summary.claimed = rows.length;
  if (rows.length === 0) return summary;

  const config = await store.config();
  const contexts = await store.contexts([...new Set(rows.map((r) => r.user_id))]);
  rows.sort((a, b) => {
    const ca = isKind(a.kind) ? categoryOrder[kinds[a.kind].category] : 9;
    const cb = isKind(b.kind) ? categoryOrder[kinds[b.kind].category] : 9;
    return ca - cb || a.id - b.id;
  });

  // Primero se decide todo (en orden, por el tope), después se manda en
  // paralelo.
  const sentThisRun = new Map<string, number>();
  const toSend: OutboxRow[] = [];
  for (const row of rows) {
    const ctx = contexts.get(row.user_id);
    const d = decide(row, ctx, config, now(), sentThisRun.get(row.user_id) ?? 0);
    if (d.action === "send") {
      toSend.push(row);
      if (isKind(row.kind) && kinds[row.kind].category === "automatic") {
        sentThisRun.set(row.user_id, (sentThisRun.get(row.user_id) ?? 0) + 1);
      }
    } else if (d.action === "defer") {
      await store.finish(row.id, "pending", d.reason, d.until);
      summary.deferred++;
    } else {
      await store.finish(row.id, "skipped", d.reason);
      summary.skipped[d.reason] = (summary.skipped[d.reason] ?? 0) + 1;
    }
  }

  const queue = [...toSend];
  const worker = async () => {
    for (let row = queue.shift(); row; row = queue.shift()) {
      const delivered = await sendOne(store, sender, row, contexts.get(row.user_id)!, summary);
      if (delivered) summary.sent++;
      else summary.failed++;
    }
  };
  await Promise.all(Array.from({ length: opts.concurrency ?? 8 }, worker));
  return summary;
}

async function sendOne(
  store: DispatchStore,
  sender: PushSender,
  row: OutboxRow,
  ctx: UserContext,
  summary: DispatchSummary,
): Promise<boolean> {
  if (!isKind(row.kind)) return false;
  const meta = kinds[row.kind];
  const logId = await store.beginLog(row.id);
  const invalid: string[] = [];
  let delivered = 0;
  await Promise.all(ctx.devices.map(async (device) => {
    const text = render(row.kind as never, row.data ?? {}, {
      locale: (device.locale === "en" ? "en" : "es") as Locale,
      showAmounts: ctx.prefs.show_amounts === true,
    });
    const result = await sender.send({
      token: device.token,
      title: text.title,
      body: text.body,
      data: {
        kind: row.kind,
        log_id: String(logId),
        route: text.route,
        ...text.routeArgs,
      },
      androidChannel: meta.androidChannel,
      interruption: meta.interruption,
      threadId: row.kind,
    });
    if (result === "ok") delivered++;
    else if (result === "invalid_token") invalid.push(device.id);
  }));
  if (invalid.length > 0) {
    await store.deleteDevices(invalid);
    summary.invalidTokens += invalid.length;
  }
  await store.complete(row.id, logId, delivered);
  return delivered > 0;
}

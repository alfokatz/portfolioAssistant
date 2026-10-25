// Fakes de las notificaciones push: store del despacho en memoria (misma
// semántica que las RPCs de 20261011000000_push_notifications.sql) y FCM
// falso. Los usan notify_dispatch_test.ts y market_watch_test.ts.

import type { FcmMessage, PushSender, SendResult } from "../notify-dispatch/fcm.ts";
import type { DispatchStore, OutboxRow, Prefs, PushConfig, UserContext } from "../notify-dispatch/store.ts";

export const defaultPrefs: Prefs = {
  enabled: true,
  price_alerts: true,
  big_moves: true,
  portfolio_moves: true,
  weekly_report: true,
  earnings: true,
  service: true,
  big_move_sensitivity: "normal",
  quiet_start: "22:00:00",
  quiet_end: "08:00:00",
  show_amounts: false,
};

export class MemoryDispatchStore implements DispatchStore {
  cfg: PushConfig = { enabled: true, allowUsers: [], kinds: {} };
  rows: (OutboxRow & { status: string; skip_reason?: string; not_before: number })[] = [];
  ctx = new Map<string, UserContext>();
  logs: { id: number; outbox_id: number; device_count: number }[] = [];
  deletedDevices: string[] = [];
  #id = 0;

  constructor(private readonly now: () => number) {}

  add(userId: string, kind: string, data: Record<string, unknown> = {}, createdAt?: number) {
    const id = ++this.#id;
    this.rows.push({
      id,
      user_id: userId,
      kind,
      dedupe_key: `${kind}:${id}`,
      data,
      created_at: new Date(createdAt ?? this.now()).toISOString(),
      attempts: 0,
      status: "pending",
      not_before: this.now(),
    });
    return id;
  }
  user(id: string, over: Partial<UserContext> = {}, prefs: Partial<Prefs> = {}) {
    this.ctx.set(id, {
      tier: "premium",
      devices: [{ id: `dev-${id}`, token: `tok-${id}`, platform: "ios", locale: "es", timezone: "America/Argentina/Buenos_Aires" }],
      automaticLast24h: 0,
      ...over,
      prefs: { ...defaultPrefs, ...prefs },
    });
  }
  row(id: number) {
    return this.rows.find((r) => r.id === id)!;
  }

  config() {
    return Promise.resolve(this.cfg);
  }
  claim(limit: number) {
    const ready = this.rows.filter((r) => r.status === "pending" && r.not_before <= this.now()).slice(0, limit);
    for (const r of ready) {
      r.status = "sending";
      r.attempts++;
    }
    return Promise.resolve(ready.map((r) => ({ ...r })));
  }
  contexts(ids: string[]) {
    return Promise.resolve(new Map(ids.filter((i) => this.ctx.has(i)).map((i) => [i, this.ctx.get(i)!])));
  }
  finish(id: number, status: "skipped" | "pending", reason: string, notBefore?: number) {
    const r = this.row(id);
    r.status = status;
    r.skip_reason = reason;
    if (notBefore) r.not_before = notBefore;
    return Promise.resolve();
  }
  beginLog(outboxId: number) {
    const id = this.logs.length + 1;
    this.logs.push({ id, outbox_id: outboxId, device_count: 0 });
    return Promise.resolve(id);
  }
  complete(outboxId: number, logId: number, deviceCount: number) {
    const r = this.row(outboxId);
    if (deviceCount > 0) {
      this.logs.find((l) => l.id === logId)!.device_count = deviceCount;
      r.status = "sent";
    } else {
      this.logs = this.logs.filter((l) => l.id !== logId);
      r.status = r.attempts >= 3 ? "failed" : "pending";
    }
    return Promise.resolve();
  }
  deleteDevices(ids: string[]) {
    this.deletedDevices.push(...ids);
    for (const c of this.ctx.values()) c.devices = c.devices.filter((d) => !ids.includes(d.id));
    return Promise.resolve();
  }
}

export class FakeSender implements PushSender {
  sent: FcmMessage[] = [];
  results = new Map<string, SendResult>();
  send(m: FcmMessage) {
    this.sent.push(m);
    return Promise.resolve(this.results.get(m.token) ?? "ok");
  }
}


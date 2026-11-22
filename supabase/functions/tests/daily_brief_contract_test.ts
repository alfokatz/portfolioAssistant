// Los fixtures de `test/fixtures/daily_brief/*.json` cumplen el contrato de
// `daily-brief/contract.ts` (flutter y assistant arrancan contra ellos). Puro.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { errorTypes, newsStatuses, scopes } from "../daily-brief/contract.ts";

const dir = new URL("../../../test/fixtures/daily_brief/", import.meta.url);
const read = (name: string) => JSON.parse(Deno.readTextFileSync(new URL(name, dir)));

const bundles = ["bundle_brief_full", "bundle_brief_numbers", "bundle_feed_premium", "bundle_feed_free", "bundle_market", "bundle_topic", "bundle_feed_unavailable", "bundle_feed_empty"];

function assertBundle(b: Record<string, unknown>, name: string) {
  assertEquals(b.status, "ok", name);
  for (const k of ["as_of", "plan", "mine", "locked", "earnings", "topics", "market", "videos", "sources", "attribution"]) {
    assert(k in b, `${name}: falta ${k}`);
  }
  const sources = b.sources as Record<string, { url: string; source: string; domain: string; title: string }>;
  const ids = new Set(Object.keys(sources));
  for (const s of Object.values(sources)) assert(s.url.startsWith("https://") && s.source && s.domain && s.title, `${name}: fuente`);
  const market = b.market as { instruments: unknown[]; pulse: { source_ids: string[]; text: string }[] };
  for (const p of market.pulse) {
    assert(p.source_ids.length > 0, `${name}: pulso sin cita`);
    for (const id of p.source_ids) assert(ids.has(id), `${name}: fuente ${id} inexistente`);
  }
  for (const t of b.topics as { status: string; summary: { source_ids: string[] }[] }[]) {
    assert(["ok", "empty", "failed"].includes(t.status));
    for (const l of t.summary) for (const id of l.source_ids) assert(ids.has(id), `${name}: fuente ${id} inexistente`);
  }
  const plan = b.plan as { tier: string; variant: string };
  assert(["free", "premium", "gold"].includes(plan.tier) && ["full", "numbers"].includes(plan.variant));
  // Free nunca trae titulares de tickers: solo el conteo.
  if (plan.variant === "numbers") {
    assertEquals(b.mine, [], name);
    assert(b.locked === null || typeof (b.locked as { mine_tickers_48h: number }).mine_tickers_48h === "number");
  } else {
    assertEquals(b.locked, null, name);
  }
  for (const m of b.mine as { id: string; kind: string; url: string; source: string; domain: string; image_url?: string }[]) {
    assert(["held", "watch"].includes(m.kind) && m.url.startsWith("https://") && m.source && m.domain, `${name}: titular`);
    assert(m.image_url === undefined || m.image_url.startsWith("https://"), `${name}: image_url`);
  }
  // Estado de `mine` (opcional): "unavailable"/"empty" solo con la lista vacía.
  const status = b.mine_status as string | undefined;
  assert(status === undefined || (newsStatuses as readonly string[]).includes(status), `${name}: mine_status`);
  if (status === "ok") assert((b.mine as unknown[]).length > 0, `${name}: ok sin titulares`);
  if (status === "empty" || status === "unavailable") assertEquals(b.mine, [], name);
  for (const s of Object.values(sources) as { image_url?: string }[]) {
    assert(s.image_url === undefined || s.image_url.startsWith("https://"), `${name}: image_url de fuente`);
  }
  for (const v of b.videos as { video_id: string; url: string; thumbnail: string }[]) {
    assert(v.url === `https://www.youtube.com/watch?v=${v.video_id}` && v.thumbnail.startsWith("https://i.ytimg.com/"));
  }
}

Deno.test("fixtures del bundle cumplen el contrato", () => {
  for (const n of bundles) assertBundle(read(`${n}.json`), n);
});

Deno.test("fixtures: Free sin tickers; temas con citas; topic trae titulares", () => {
  const free = JSON.stringify(read("bundle_brief_numbers.json"));
  assert(!/NVDA|AAPL/.test(free));
  assertEquals(read("bundle_brief_numbers.json").plan.variant, "numbers");
  assertEquals(read("bundle_brief_full.json").plan.variant, "full");
  assert(read("bundle_topic.json").topic_news.length > 0);
  // El orden de los instrumentos lo fija el catálogo: el fixture no lo reordena.
  assertEquals(read("bundle_market.json").market.instruments[0].symbol, "^GSPC");
});

Deno.test("fixtures de compare: agree exige 2 o más medios; insufficient sin puntos", () => {
  const ok = read("compare_ok.json");
  assertEquals(ok.status, "ok");
  for (const p of ok.points) {
    assert(["agree", "differ", "only"].includes(p.kind));
    const domains = new Set(p.source_ids.map((id: string) => ok.sources[id].domain));
    if (p.kind === "agree") assert(domains.size >= 2);
  }
  const bad = read("compare_insufficient.json");
  assertEquals(bad.status, "insufficient_sources");
  assertEquals(bad.points, []);
});

Deno.test("constantes del contrato", () => {
  assertEquals([...scopes], ["brief", "feed", "market", "topic"]);
  assertEquals(errorTypes.disabled, 403);
  assertEquals(errorTypes.rate_limited, 429);
});

// `GET /functions/v1/daily-brief?scope=brief|feed|market|topic&lang=es|en&day=YYYY-MM-DD[&topic=<id>]`
// con el JWT del usuario. Contrato: `contract.ts`. Spec §3.5 y §5.
//
// - El cliente NUNCA manda tickers: cartera, watchlist, temas y medios salen de
//   la base (`daily_brief_entitlement`, que deriva todo del usuario del JWT).
// - El plan se aplica acá: Free no recibe titulares de tickers (solo el conteo
//   `locked`); la watchlist y el resto de lo de Gold solo con Gold.
// - Medios silenciados filtran y preferidos reordenan, después de la caché.
// - Si falla una pieza la respuesta sigue siendo 200 con ese bloque vacío.

import { bearer, corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { readCache, writeCache } from "../_shared/data_cache.ts";
import {
  gdeltConfig,
  gdeltFetch,
  gdeltUrl,
  type Headline,
  headlinesByTicker,
  newsAllowlistMeta,
  domainsForRegions,
  parseArticles,
  regionOfSymbol,
  tickerKey,
  tickerTtlSeconds,
} from "../_shared/gdelt.ts";
import { digestFor, type DigestSpec, applySourcePrefs, remapSources, regions, type Region } from "../_shared/news_digest.ts";
import { looksLikeInstructions } from "../_shared/news_attribution.ts";
import { isRecommendation } from "../_shared/recommendation.ts";
import { fetchQuotes } from "../market-watch/quotes.ts";
import type {
  BundleResponse, Entitlement, Instrument, Lang, MarketBlock, NewsItem, PulseLine, Scope, SourceRef,
  TopicDigest, TopicNewsItem, Video,
} from "./contract.ts";
import { scopes } from "./contract.ts";

export const config = {
  ratePerMinute: 20,
  briefHeldTickers: 8,
  briefWatchTickers: 5,
  briefPerTicker: 3,
  feedPerTicker: 4,
  feedMaxTickers: 20,
  newsWindowHours: 48,
  instrumentsTtlSeconds: 10 * 60,
  maxVideosPerBlock: 3,
  videoWindowHours: 48,
};

type Db = Deps["db"];
type TopicRow = {
  id: string; label_es: string; label_en: string; query_en: string; query_es: string;
  asset_link_es: string | null; asset_link_en: string | null; auto_asset_classes: string[];
  region: string; keywords: string[];
};

const isoDay = /^\d{4}-\d{2}-\d{2}$/;

function validDay(day: string | null, nowMs: number): day is string {
  if (!day || !isoDay.test(day)) return false;
  const t = Date.parse(`${day}T00:00:00Z`);
  if (!Number.isFinite(t) || new Date(t).toISOString().slice(0, 10) !== day) return false;
  return Math.abs(t - nowMs) <= 3 * 24 * 3600 * 1000;
}

const pieceOf: Record<Scope, "feed" | "market" | "topics" | null> = {
  brief: null, feed: "feed", market: "market", topic: "topics",
};

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return typedError(405, "method_not_allowed", "GET only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  const url = new URL(req.url);
  const scope = url.searchParams.get("scope") as Scope | null;
  if (!scope || !(scopes as readonly string[]).includes(scope)) {
    return typedError(400, "invalid_scope", "scope must be brief, feed, market or topic");
  }
  if (!validDay(url.searchParams.get("day"), deps.now())) {
    return typedError(400, "invalid_day", "day must be YYYY-MM-DD (today, give or take)");
  }
  const day = url.searchParams.get("day")!;
  const lang: Lang = url.searchParams.get("lang") === "en" ? "en" : "es";
  const topicParam = url.searchParams.get("topic");
  if (scope === "topic" && !(topicParam && /^[a-z0-9_]{2,40}$/.test(topicParam))) {
    return typedError(400, "invalid_topic", "topic id expected");
  }

  const rate = await deps.db.rpc("rate_limit_hit", {
    p_user_id: userId, p_bucket: "daily_brief", p_per_minute: config.ratePerMinute,
  });
  if (rate.data === false) return typedError(429, "rate_limited", "Too many requests");

  const ent = await entitlementOf(deps.db, userId, day);
  if (!ent || !ent.enabled) return typedError(403, "disabled", "daily brief is off");
  const piece = pieceOf[scope];
  if (piece && !ent.pieces[piece]) return typedError(403, "disabled", `${piece} is off`);

  const started = Date.now();
  const body = await build(deps, scope, ent, lang, day, topicParam);
  if (body === "invalid_topic") return typedError(400, "invalid_topic", "unknown topic");
  console.log(JSON.stringify({ fn: "daily-brief", scope, variant: ent.variant, ms: Date.now() - started }));
  return json(200, body);
}

async function entitlementOf(db: Db, userId: string, day: string): Promise<Entitlement | null> {
  const { data, error } = await db.rpc("daily_brief_entitlement", { p_user_id: userId, p_day: day });
  if (error || !data) {
    console.error("[daily-brief] entitlement", error?.message);
    return null;
  }
  return data as Entitlement;
}

const hoursAgo = (iso: string, nowMs: number) => (nowMs - Date.parse(iso)) / 3600_000;

/// Titulares recientes de un ticker, sin silenciados, preferidos primero y
/// después los más nuevos.
export function pickNews(
  list: Headline[], nowMs: number, prefer: Set<string>, mute: Set<string>, max: number,
): (Headline & { preferred: boolean })[] {
  return list
    .filter((h) =>
      !mute.has(h.domain) && !isRecommendation(h.title) && !looksLikeInstructions(h.title) &&
      hoursAgo(h.published_at, nowMs) <= config.newsWindowHours && Date.parse(h.published_at) <= nowMs + 5 * 60_000
    )
    .map((h) => ({ ...h, preferred: prefer.has(h.domain) }))
    .sort((a, b) => Number(b.preferred) - Number(a.preferred) || b.published_at.localeCompare(a.published_at))
    .slice(0, max);
}

/// Conteo de tickers con titular en 48 h, mirando SOLO la caché (Free: nunca se
/// consulta GDELT por usuario).
async function lockedCount(deps: Deps, symbols: string[], day: string, mute: Set<string>): Promise<number> {
  const lists = await Promise.all(symbols.map((s) => readCache<{ items: Headline[] }>(deps, tickerKey(s, day)).catch(() => null)));
  return lists.filter((c) => c && pickNews(c.body.items ?? [], deps.now(), new Set(), mute, 1).length > 0).length;
}

async function build(
  deps: Deps, scope: Scope, ent: Entitlement, lang: Lang, day: string, topicId: string | null,
): Promise<BundleResponse | "invalid_topic"> {
  const nowMs = deps.now();
  const prefer = new Set(ent.prefer), mute = new Set(ent.mute);
  const full = ent.variant === "full";
  const rows = await newsAllowlistMeta(deps);
  const allow = new Map(rows.map((r) => [r.domain, r.name]));
  const topics = await loadTopics(deps.db);
  const topicById = new Map(topics.map((t) => [t.id, t]));
  if (scope === "topic" && !topicById.has(topicId!)) return "invalid_topic";

  const out: BundleResponse = {
    status: "ok",
    as_of: new Date(nowMs).toISOString(),
    plan: { tier: ent.tier, variant: ent.variant, courtesy: ent.courtesy },
    mine: [], locked: null, earnings: [], topics: [],
    market: { instruments: [], pulse: [] }, videos: [], sources: {},
    attribution: { videos: "YouTube" },
  };
  const heldSymbols = ent.held.map((h) => h.symbol);
  const primaryRegion = primaryRegionOf(ent) as Region;

  // Lo tuyo (Premium, cortesía y Gold); Gold suma la watchlist.
  if ((scope === "brief" || scope === "feed") && full) {
    const isBrief = scope === "brief";
    const held = heldSymbols.slice(0, isBrief ? config.briefHeldTickers : config.feedMaxTickers);
    const watch = ent.tier === "gold"
      ? ent.watchlist.filter((s) => !heldSymbols.includes(s)).slice(0, isBrief ? config.briefWatchTickers : 10)
      : [];
    const { byTicker } = await headlinesByTicker(deps, [...held, ...watch], day, { allow, rows });
    let n = 0;
    const add = (symbols: string[], kind: "held" | "watch") => {
      for (const sym of symbols) {
        for (const h of pickNews(byTicker[sym] ?? [], nowMs, prefer, mute, isBrief ? config.briefPerTicker : config.feedPerTicker)) {
          out.mine.push({
            id: `h${++n}`, ticker: sym, kind, title: h.title, source: h.source, domain: h.domain,
            url: h.url, published_at: h.published_at, lang: h.language, preferred: h.preferred,
          } satisfies NewsItem);
        }
      }
    };
    add(held, "held");
    add(watch, "watch");
  } else if (scope === "feed") {
    out.locked = { mine_tickers_48h: await lockedCount(deps, heldSymbols, day, mute) };
  }
  if (scope === "brief") out.asset_classes = ent.asset_classes;

  const wantsDigest = (spec: DigestSpec) => digestFor(deps, spec, allow);
  const pulseOf = async (region: Region) => {
    const d = await wantsDigest({ kind: "pulse", region, lang });
    return d && d.status === "ok" ? { ...applySourcePrefs(d, prefer, mute), topic: null as string | null } : null;
  };
  const topicDigest = async (t: TopicRow) =>
    await wantsDigest({ kind: "topic", topicId: t.id, query: lang === "en" ? t.query_en : t.query_es, lang });

  if (scope === "brief") {
    const pulses: PulseLine[] = [];
    const parts: { lines: { text: string; source_ids: string[] }[]; sources: Record<string, never | SourceRef> }[] = [];
    const meta: { topic_id: string | null; t?: TopicRow }[] = [];
    const max = full ? 3 : 1;
    if (full && ent.pieces.topics) {
      for (const id of ent.topics.slice(0, 3)) {
        const t = topicById.get(id);
        if (!t) continue;
        const d = await topicDigest(t);
        if (!d || d.status !== "ok") continue;
        const p = applySourcePrefs(d, prefer, mute);
        if (p.lines.length > 0) { parts.push({ lines: p.lines.slice(0, 1), sources: p.sources }); meta.push({ topic_id: id, t }); }
      }
    }
    if (parts.length < max && ent.pieces.market) {
      const p = await pulseOf(primaryRegion);
      if (p && p.lines.length > 0) { parts.push({ lines: p.lines.slice(0, max - parts.length), sources: p.sources }); meta.push({ topic_id: null }); }
    }
    const mapped = remapSources(parts, "p");
    Object.assign(out.sources, mapped.sources);
    mapped.lines.forEach((lines, i) => {
      for (const l of lines) {
        const t = meta[i].t;
        const cls = t?.auto_asset_classes?.[0] ?? null;
        const link = t && cls && ent.asset_classes.includes(cls) ? (lang === "en" ? t.asset_link_en : t.asset_link_es) : null;
        pulses.push({
          text: l.text, source_ids: l.source_ids, topic_id: meta[i].topic_id,
          ...(full ? { asset_link: link, asset_class: link ? cls : null } : {}),
        });
      }
    });
    out.market.pulse = pulses.slice(0, max);
  }

  if (scope === "feed" || scope === "topic") {
    const ids = scope === "topic" ? [topicId!] : ent.topics;
    const chosen = ids.map((id) => topicById.get(id)).filter((t): t is TopicRow => !!t);
    const digests = await Promise.all(chosen.map(topicDigest));
    const prefs = digests.map((d) => d && d.status === "ok" ? applySourcePrefs(d, prefer, mute) : null);
    const mapped = remapSources(prefs.filter((p): p is NonNullable<typeof p> => !!p), "c");
    Object.assign(out.sources, mapped.sources);
    let k = 0;
    out.topics = chosen.map((t, i): TopicDigest => {
      const p = prefs[i];
      const lines = p ? mapped.lines[k++] : [];
      return {
        topic_id: t.id, label: lang === "en" ? t.label_en : t.label_es,
        status: p && lines.length > 0 ? "ok" : "empty",
        summary: lines, as_of: digests[i]?.as_of ?? null,
      };
    });
  }

  if (scope === "topic") out.topic_news = await topicNews(deps, topicById.get(topicId!)!, day, rows, prefer, mute);

  if (scope === "market") {
    out.market = await marketBlock(deps, ent, lang, allow, prefer, mute, out.sources);
  }

  if (ent.pieces.videos && (scope === "feed" || scope === "market" || scope === "topic")) {
    out.videos = await videosFor(deps.db, nowMs, scope === "market" ? [] : scope === "topic" ? [topicId!] : ent.topics, scope === "market", prefer);
  }
  return out;
}

/// Región con más peso en la cartera (sufijo de la bolsa); `us` si no hay.
export function primaryRegionOf(ent: Pick<Entitlement, "held">): string {
  const w: Record<string, number> = {};
  for (const h of ent.held) {
    const r = regionOfSymbol(h.symbol);
    if (r === "global") continue;
    w[r] = (w[r] ?? 0) + (h.weight_pct ?? 1);
  }
  const best = Object.entries(w).sort((a, b) => b[1] - a[1])[0]?.[0];
  return best && (regions as readonly string[]).includes(best) ? best : "us";
}

async function loadTopics(db: Db): Promise<TopicRow[]> {
  const { data } = await db.from("news_topics")
    .select("id, label_es, label_en, query_en, query_es, asset_link_es, asset_link_en, auto_asset_classes, region, keywords")
    .eq("enabled", true).order("sort");
  return (data ?? []) as TopicRow[];
}

async function marketBlock(
  deps: Deps, ent: Entitlement, lang: Lang, allow: Map<string, string>,
  prefer: Set<string>, mute: Set<string>, sources: Record<string, SourceRef>,
): Promise<MarketBlock> {
  const { data } = await deps.db.from("market_reference_instruments")
    .select("symbol, kind, label_es, label_en, markets, core").eq("enabled", true).order("sort");
  const list = ((data ?? []) as { symbol: string; kind: Instrument["kind"]; label_es: string; label_en: string; markets: string[]; core: boolean }[])
    .filter((r) => r.core || r.markets.some((m) => ent.markets.includes(m)));
  const key = `refquotes:${list.map((r) => r.symbol).join(",")}`;
  type Q = Record<string, { pct: number | null; as_of: string | null }>;
  let quotes: Q = {};
  const hit = await readCache<Q>(deps, key);
  if (hit && hit.ageSeconds < config.instrumentsTtlSeconds) quotes = hit.body;
  else {
    try {
      const got = await fetchQuotes(deps, list.map((r) => r.symbol));
      for (const [s, q] of got) {
        quotes[s] = {
          pct: q.changePct, as_of: q.regularMarketTime ? new Date(q.regularMarketTime * 1000).toISOString() : null,
        };
      }
      if (Object.keys(quotes).length > 0) await writeCache(deps, key, quotes);
      else if (hit) quotes = hit.body;
    } catch {
      if (hit) quotes = hit.body;
    }
  }
  // Orden fijo por catálogo, nunca por tamaño del movimiento.
  const instruments = list.map((r): Instrument => ({
    symbol: r.symbol, label: lang === "en" ? r.label_en : r.label_es, kind: r.kind,
    pct: quotes[r.symbol]?.pct ?? null, as_of: quotes[r.symbol]?.as_of ?? null,
  }));
  const regs = [...new Set([primaryRegionOf(ent), ...ent.held.map((h) => regionOfSymbol(h.symbol))])]
    .filter((r): r is Region => (regions as readonly string[]).includes(r)).slice(0, 4);
  const digests = await Promise.all(regs.map((r) => digestFor(deps, { kind: "pulse", region: r, lang }, allow)));
  const parts = digests.map((d) => d && d.status === "ok" ? applySourcePrefs(d, prefer, mute) : null)
    .filter((p): p is NonNullable<typeof p> => !!p);
  const mapped = remapSources(parts, "p");
  Object.assign(sources, mapped.sources);
  const pulse: PulseLine[] = mapped.lines.flat().map((l) => ({ text: l.text, source_ids: l.source_ids, topic_id: null }));
  return { instruments, pulse };
}

/// Titulares de la allowlist que nombran al tema (caché GDELT por tema).
async function topicNews(
  deps: Deps, t: TopicRow, day: string, rows: Awaited<ReturnType<typeof newsAllowlistMeta>>,
  prefer: Set<string>, mute: Set<string>,
): Promise<TopicNewsItem[]> {
  const key = `gdelt:topic:${t.id}:${day}`;
  let items: Headline[] = [];
  const hit = await readCache<{ items: Headline[] }>(deps, key).catch(() => null);
  if (hit && hit.ageSeconds < tickerTtlSeconds(deps.now())) items = hit.body.items;
  else {
    try {
      const allow = new Map(rows.map((r) => [r.domain, r.name]));
      const url = gdeltUrl([t.label_en], [...allow.keys()], { domains: domainsForRegions(rows, [t.region]) });
      items = parseArticles(await gdeltFetch(deps, url, gdeltConfig.maxWaitMs), allow).slice(0, 12);
      await writeCache(deps, key, { items });
    } catch (e) {
      console.error("[daily-brief] topic news", String(e));
      items = hit?.body.items ?? [];
    }
  }
  return pickNews(items, deps.now(), prefer, mute, 6).map((h, i) => ({
    id: `n${i + 1}`, title: h.title, source: h.source, domain: h.domain, url: h.url,
    published_at: h.published_at, lang: h.language, preferred: h.preferred,
  }));
}

/// Videos de canales de la allowlist (últimas 48 h): de los temas dados o, con
/// [marketOnly], los generales (sin tema). Hasta 3, preferidos primero.
async function videosFor(db: Db, nowMs: number, topicIds: string[], marketOnly: boolean, prefer: Set<string>): Promise<Video[]> {
  const since = new Date(nowMs - config.videoWindowHours * 3600_000).toISOString();
  const { data, error } = await db.from("news_videos")
    .select("video_id, title, published_at, topic_ids, channel:video_channel_allowlist(name, outlet_domain, enabled)")
    .gte("published_at", since).order("published_at", { ascending: false }).limit(60);
  if (error || !data) return [];
  type Row = { video_id: string; title: string; published_at: string; topic_ids: string[]; channel: { name: string; outlet_domain: string | null; enabled: boolean } | null };
  return (data as unknown as Row[])
    .filter((v) => v.channel?.enabled && !isRecommendation(v.title) &&
      (marketOnly ? v.topic_ids.length === 0 : v.topic_ids.some((t) => topicIds.includes(t))))
    .sort((a, b) => Number(prefer.has(b.channel!.outlet_domain ?? "")) - Number(prefer.has(a.channel!.outlet_domain ?? "")))
    .slice(0, config.maxVideosPerBlock)
    .map((v) => ({
      video_id: v.video_id, title: v.title, channel: v.channel!.name, published_at: v.published_at,
      topic_id: marketOnly ? null : v.topic_ids.find((t) => topicIds.includes(t)) ?? null,
      url: `https://www.youtube.com/watch?v=${v.video_id}`,
      thumbnail: `https://i.ytimg.com/vi/${v.video_id}/mqdefault.jpg`,
    }));
}

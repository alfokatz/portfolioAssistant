// news-warm: calentamiento del brief diario (spec §3.8). Lo llama pg_cron cada
// 15 minutos (`_call_function('news-warm')`, solo si el interruptor
// `daily_brief` está prendido para alguien) con el header `x-cron-secret`.
//
// Tres trabajos, independientes (si uno falla, los otros siguen):
//
// 1. Titulares: en los husos donde son entre las 6:00 y las 7:45, los 200
//    símbolos más tenidos (`daily_brief_warm_symbols`) pasan por
//    `headlinesByTicker`: hasta 6 lotes de GDELT por corrida (unos 35 s).
// 2. Pulso y temas: a las 6:30 de cada región (us: America/New_York, eu:
//    Europe/Madrid, latam: America/Argentina/Buenos_Aires, asia: Asia/Tokyo),
//    durante 45 minutos (3 corridas: las repetidas no cuestan, la clave ya
//    está fresca), se genera el pulso de la región y el digest de cada tema que
//    tenga usuarios allí, SOLO en los idiomas que tienen usuarios
//    (`daily_brief_warm_plan`). Costo fijo: las franjas por día salen de
//    `app_config.daily_brief_costs` (1 por defecto) y `max_digests_per_run`
//    acota cada corrida. Después de eso, la generación es perezosa
//    (`digestFor` en `daily-brief`).
// 3. Videos: cada 30 minutos, `playlistItems.list` de los canales habilitados
//    (YouTube Data API; sin `YOUTUBE_API_KEY` no se hace nada).
//
// Cada pieza respeta su sub-interruptor (`pieces`): `feed`/`push` →
// titulares, `market` → pulso, `topics` → temas, `videos` → videos.

import { corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { isCronRequest } from "../_shared/cron.ts";
import { headlinesByTicker, newsAllowlistMeta } from "../_shared/gdelt.ts";
import {
  type DigestCosts,
  type DigestSpec,
  generateAndCache,
  loadDigestCosts,
  type Region,
  regions,
  readDigest,
} from "../_shared/news_digest.ts";
import {
  fetchPlaylist,
  type TopicKeywords,
  type VideoChannel,
  videoRows,
  youtubeConfig,
} from "./youtube.ts";

export type WarmDeps = Pick<Deps, "db" | "fetch" | "env" | "now" | "background">;

export const warmConfig = {
  /// Titulares: husos entre 6:00 y 7:45 locales (minutos del día).
  headlines: { fromMin: 6 * 60, toMin: 7 * 60 + 45 },
  maxHeadlineBatches: 6,
  symbolsPerGroup: 200,
  /// Pulso y temas: desde las 6:30 locales de cada región, 45 minutos.
  digests: { fromMin: 6 * 60 + 30, toMin: 7 * 60 + 15 },
  digestConcurrency: 4,
  /// No se arranca un digest nuevo pasado esto: con el timeout del digest
  /// (40 s) el último termina antes de que la función corte (~55 s).
  digestStartBudgetMs: 10_000,
  /// Videos: en las corridas de los minutos 0 y 30 (el cron es cada 15).
  videosEveryMinutes: 30,
  videoUpsertChunk: 200,
};

/// La zona que marca la hora de cada región (spec §3.8).
export const regionClock: Record<Region, string> = {
  us: "America/New_York",
  eu: "Europe/Madrid",
  latam: "America/Argentina/Buenos_Aires",
  asia: "Asia/Tokyo",
};

/// Minutos desde la medianoche en [timeZone] a la hora [ms].
export function localMinutes(ms: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    .formatToParts(new Date(ms));
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value ?? 0);
  return get("hour") * 60 + get("minute");
}

export const inWindow = (minutes: number, w: { fromMin: number; toMin: number }) =>
  minutes >= w.fromMin && minutes < w.toMin;

type Pieces = { headlines: boolean; market: boolean; topics: boolean; videos: boolean };

async function readPieces(deps: Pick<Deps, "db">): Promise<Pieces> {
  const ask = async (key: string) => (await deps.db.rpc("_daily_brief_piece", { p_key: key })).data !== false;
  const [feed, push, market, topics, videos] = await Promise.all(["feed", "push", "market", "topics", "videos"].map(ask));
  return { headlines: feed || push, market, topics, videos };
}

// ---------------------------------------------------------------------------
// 1. Titulares
// ---------------------------------------------------------------------------

export type HeadlinesSummary = { zones: number; symbols: number; fetched: number; pending: number };

export async function warmHeadlines(deps: WarmDeps): Promise<HeadlinesSummary> {
  const summary: HeadlinesSummary = { zones: 0, symbols: 0, fetched: 0, pending: 0 };
  const { data, error } = await deps.db.rpc("daily_brief_warm_zones", {
    p_from_min: warmConfig.headlines.fromMin,
    p_to_min: warmConfig.headlines.toMin,
  });
  if (error) throw new Error(`warm_zones: ${error.message}`);
  const zones = (data ?? []) as { timezone: string; local_date: string }[];
  summary.zones = zones.length;
  // La clave de caché lleva la fecha LOCAL del usuario: una consulta por fecha.
  const byDate = new Map<string, string[]>();
  for (const z of zones) byDate.set(String(z.local_date), [...(byDate.get(String(z.local_date)) ?? []), z.timezone]);

  let batches = warmConfig.maxHeadlineBatches;
  for (const [day, timezones] of byDate) {
    if (batches <= 0) break;
    const sym = await deps.db.rpc("daily_brief_warm_symbols", {
      p_timezones: timezones, p_limit: warmConfig.symbolsPerGroup,
    });
    if (sym.error) throw new Error(`warm_symbols: ${sym.error.message}`);
    const symbols = ((sym.data ?? []) as { symbol: string }[]).map((r) => r.symbol);
    if (symbols.length === 0) continue;
    summary.symbols += symbols.length;
    const res = await headlinesByTicker(deps, symbols, day, { maxBatches: batches });
    summary.fetched += res.fetched;
    summary.pending += res.pending.length;
    batches -= Math.max(res.fetched, 1);
  }
  return summary;
}

// ---------------------------------------------------------------------------
// 2. Pulso y temas
// ---------------------------------------------------------------------------

type TopicRow = { id: string; query_en: string; query_es: string };

export type PlanRow = { lang: string; topic_id: string | null; users: number };

/// Qué digests hay que tener listos para una región: el pulso (si `market`) y
/// los temas (si `topics`) de cada idioma con usuarios. Puro.
export function digestSpecs(
  region: Region,
  plan: PlanRow[],
  topics: TopicRow[],
  pieces: Pick<Pieces, "market" | "topics">,
): DigestSpec[] {
  const byId = new Map(topics.map((t) => [t.id, t]));
  const out: DigestSpec[] = [];
  const langs = [...new Set(plan.filter((p) => p.users > 0 && (p.lang === "es" || p.lang === "en")).map((p) => p.lang as "es" | "en"))]
    .sort();
  for (const lang of langs) {
    if (pieces.market && plan.some((p) => p.lang === lang && p.topic_id === null && p.users > 0)) {
      out.push({ kind: "pulse", region, lang });
    }
    if (!pieces.topics) continue;
    const ids = plan.filter((p) => p.lang === lang && p.topic_id !== null && p.users > 0).map((p) => p.topic_id!).sort();
    for (const id of ids) {
      const t = byId.get(id);
      if (t) out.push({ kind: "topic", topicId: id, query: lang === "en" ? t.query_en : t.query_es, lang });
    }
  }
  return out;
}

export type DigestsSummary = {
  regions: string[];
  wanted: number;
  fresh: number;
  generated: number;
  failed: number;
  skipped_by_cap: number;
};

/// Corre [tasks] con [limit] en paralelo; deja de arrancar nuevas pasado [until].
async function pool<T>(items: T[], limit: number, until: number, now: () => number, run: (item: T) => Promise<void>) {
  let next = 0;
  const worker = async () => {
    while (next < items.length && now() < until) await run(items[next++]);
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return next;
}

export async function warmDigests(deps: WarmDeps, pieces: Pieces, costs: DigestCosts): Promise<DigestsSummary> {
  const summary: DigestsSummary = { regions: [], wanted: 0, fresh: 0, generated: 0, failed: 0, skipped_by_cap: 0 };
  if (!pieces.market && !pieces.topics) return summary;
  const now = deps.now();
  const due = regions.filter((r) => inWindow(localMinutes(now, regionClock[r]), warmConfig.digests));
  summary.regions = [...due];
  if (due.length === 0) return summary;

  const [rows, topicsRes] = await Promise.all([
    newsAllowlistMeta(deps),
    deps.db.from("news_topics").select("id, query_en, query_es").eq("enabled", true),
  ]);
  const allow = new Map(rows.map((r) => [r.domain, r.name]));
  const topics = (topicsRes.data ?? []) as TopicRow[];

  const specs: DigestSpec[] = [];
  for (const region of due) {
    const plan = await deps.db.rpc("daily_brief_warm_plan", { p_region: region });
    if (plan.error) throw new Error(`warm_plan: ${plan.error.message}`);
    specs.push(...digestSpecs(region, (plan.data ?? []) as PlanRow[], topics, pieces));
  }
  summary.wanted = specs.length;

  // Lo que ya está fresco no cuesta; el resto, hasta el tope de la corrida.
  const missing: DigestSpec[] = [];
  for (const spec of specs) {
    const found = await readDigest(deps, spec, costs);
    if (found?.fresh) summary.fresh++;
    else missing.push(spec);
  }
  const todo = missing.slice(0, costs.maxDigestsPerRun);
  summary.skipped_by_cap = missing.length - todo.length;

  const started = await pool(todo, warmConfig.digestConcurrency, now + warmConfig.digestStartBudgetMs, deps.now, async (spec) => {
    const body = await generateAndCache(deps, spec, allow, costs).catch((e) => {
      console.error("[news-warm] digest", String(e));
      return null;
    });
    // null = otro generador tiene el arriendo, falló o no hay clave.
    if (body) summary.generated++;
    else summary.failed++;
  });
  summary.skipped_by_cap += todo.length - started;
  return summary;
}

// ---------------------------------------------------------------------------
// 3. Videos
// ---------------------------------------------------------------------------

export type VideosSummary = { status: "ok" | "no_key" | "not_due" | "no_channels" | "quota"; channels: number; stored: number };

export async function warmVideos(deps: WarmDeps): Promise<VideosSummary> {
  const now = deps.now();
  if (new Date(now).getUTCMinutes() % warmConfig.videosEveryMinutes >= 15) {
    return { status: "not_due", channels: 0, stored: 0 };
  }
  // Sin clave: la pieza de videos devuelve vacío, sin error.
  const apiKey = deps.env("YOUTUBE_API_KEY");
  if (!apiKey) return { status: "no_key", channels: 0, stored: 0 };

  const [chans, topicsRes] = await Promise.all([
    deps.db.from("video_channel_allowlist").select("channel_id, uploads_playlist_id, lang, region, require_topic").eq("enabled", true),
    deps.db.from("news_topics").select("id, keywords").eq("enabled", true),
  ]);
  if (chans.error) throw new Error(`channels: ${chans.error.message}`);
  const channels = ((chans.data ?? []) as VideoChannel[]).slice(0, youtubeConfig.maxChannels);
  if (channels.length === 0) return { status: "no_channels", channels: 0, stored: 0 };
  const topics = ((topicsRes.data ?? []) as { id: string; keywords: string[] | null }[])
    .map((t): TopicKeywords => ({ id: t.id, keywords: t.keywords ?? [] }));

  let quota = false;
  const rows: ReturnType<typeof videoRows> = [];
  let next = 0;
  const worker = async () => {
    while (next < channels.length && !quota) {
      const channel = channels[next++];
      const res = await fetchPlaylist(deps, apiKey, channel.uploads_playlist_id);
      if (!res.ok) {
        if (res.quota) quota = true;
        continue;
      }
      rows.push(...videoRows(channel, res.videos, topics, deps.now()));
    }
  };
  await Promise.all(Array.from({ length: Math.min(youtubeConfig.concurrency, channels.length) }, worker));

  // Estado de cada video (público y embebible) en lotes de 50 ids. Sin estado
  // verificado no se guarda (cumple compliance H4); con la cuota agotada se
  // guarda lo que alcanzó a verificarse.
  const st = rows.length > 0 ? await fetchVideoStatuses(deps, apiKey, rows.map((r) => r.video_id)) : null;
  if (st && !st.ok && st.quota) quota = true;
  const verified = st ? applyVideoStatus(rows, st.statuses) : [];

  for (let i = 0; i < verified.length; i += warmConfig.videoUpsertChunk) {
    const { error } = await deps.db.from("news_videos").upsert(verified.slice(i, i + warmConfig.videoUpsertChunk), { onConflict: "video_id" });
    if (error) throw new Error(`news_videos upsert: ${error.message}`);
  }
  return { status: quota ? "quota" : "ok", channels: channels.length, stored: verified.length };
}

// ---------------------------------------------------------------------------
// Entrada
// ---------------------------------------------------------------------------

export type WarmSummary = {
  headlines: HeadlinesSummary | { error: string } | null;
  digests: DigestsSummary | { error: string } | null;
  videos: VideosSummary | { error: string } | null;
};

const failure = (e: unknown) => ({ error: e instanceof Error ? e.message.slice(0, 200) : "error" });

export async function runWarm(deps: WarmDeps): Promise<WarmSummary | { skipped: "off" }> {
  const on = await deps.db.rpc("_daily_brief_cron_on");
  if (on.data !== true) return { skipped: "off" };
  const [pieces, costs] = await Promise.all([readPieces(deps), loadDigestCosts(deps)]);
  const [headlines, digests, videos] = await Promise.all([
    pieces.headlines ? warmHeadlines(deps).catch(failure) : Promise.resolve(null),
    warmDigests(deps, pieces, costs).catch(failure),
    pieces.videos ? warmVideos(deps).catch(failure) : Promise.resolve(null),
  ]);
  return { headlines, digests, videos };
}

export async function handle(req: Request, deps: WarmDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");
  if (!isCronRequest(req, deps)) return typedError(401, "unauthorized", "Missing or invalid cron secret");
  const started = Date.now();
  const summary = await runWarm(deps);
  console.log(JSON.stringify({ fn: "news-warm", ms: Date.now() - started, ...summary }));
  return json(200, summary);
}

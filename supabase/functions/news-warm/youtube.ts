// Videos de canales de medios (spec §3.8, D4). YouTube Data API v3 con
// `playlistItems.list` sobre la lista de subidas de cada canal de la allowlist
// (`video_channel_allowlist`): 1 unidad de cuota por canal y por lectura.
// NUNCA `search.list` (100 unidades por llamada).
//
// - La clave vive solo en el secreto `YOUTUBE_API_KEY` de la función. Sin
//   clave no se hace nada y no es un error (la pieza de videos viene vacía).
// - Solo mercado y temas: los videos se asignan a temas por palabras clave del
//   título, sin LLM. Nunca por ticker.
// - Se guarda metadata mínima (id, título, fecha, canal, idioma, temas): se
//   purga a los 7 días (las políticas de YouTube piden refrescar o borrar a
//   los 30).
// - La clave va en la URL de la API: jamás se loguea la URL ni el cuerpo de un
//   error.

import type { Deps } from "../_shared/common.ts";
import { looksLikeInstructions, mentions } from "../_shared/news_attribution.ts";
import { isRecommendation } from "../_shared/recommendation.ts";

export const youtubeConfig = {
  url: "https://www.googleapis.com/youtube/v3/playlistItems",
  maxResults: 10,
  /// Canales por corrida (30 canales × 48 lecturas = 1.440 unidades de las
  /// 10.000 diarias).
  maxChannels: 40,
  concurrency: 5,
  timeoutMs: 10_000,
  /// Solo se guarda lo publicado en este lapso (se sirve hasta 48 h).
  maxAgeHours: 72,
};

export type VideoChannel = {
  channel_id: string;
  uploads_playlist_id: string;
  lang: "es" | "en";
  region: string;
};

export type TopicKeywords = { id: string; keywords: string[] };

export type PlaylistVideo = { video_id: string; title: string; published_at: string };

export type VideoRow = {
  video_id: string;
  channel_id: string;
  title: string;
  published_at: string;
  lang: "es" | "en";
  topic_ids: string[];
  region: string;
  fetched_at: string;
};

const videoIdPattern = /^[A-Za-z0-9_-]{11}$/;

/// Items de `playlistItems.list` → videos públicos. Descarta los privados o
/// borrados (YouTube los deja en la lista con ese título), los sin fecha y los
/// ids que no son de un video.
export function parsePlaylistItems(body: unknown): PlaylistVideo[] {
  const items = (body as { items?: unknown[] })?.items;
  if (!Array.isArray(items)) return [];
  const out: PlaylistVideo[] = [];
  for (const it of items as Record<string, unknown>[]) {
    const snippet = (it.snippet ?? {}) as Record<string, unknown>;
    const details = (it.contentDetails ?? {}) as Record<string, unknown>;
    const resource = (snippet.resourceId ?? {}) as Record<string, unknown>;
    const id = String(details.videoId ?? resource.videoId ?? "");
    const title = typeof snippet.title === "string" ? snippet.title.replace(/\s+/g, " ").trim() : "";
    // `videoPublishedAt` es cuándo se publicó el video; `publishedAt` del
    // snippet es cuándo se agregó a la lista (igual para subidas).
    const published = String(details.videoPublishedAt ?? snippet.publishedAt ?? "");
    if (!videoIdPattern.test(id) || title === "" || !Number.isFinite(Date.parse(published))) continue;
    if (/^(private|deleted) video$/i.test(title)) continue;
    out.push({ video_id: id, title, published_at: new Date(published).toISOString() });
  }
  return out;
}

/// Temas del catálogo cuyas palabras clave (es+en) aparecen en el título.
/// Sin ninguno, el video es "de mercado" (general).
export function assignTopics(title: string, topics: TopicKeywords[]): string[] {
  return topics.filter((t) => t.keywords.some((k) => k.trim().length >= 2 && mentions(title, k))).map((t) => t.id);
}

/// De los videos de un canal, las filas a guardar: recientes, sin consejo ni
/// órdenes escondidas en el título, con sus temas.
export function videoRows(
  channel: VideoChannel,
  videos: PlaylistVideo[],
  topics: TopicKeywords[],
  nowMs: number,
): VideoRow[] {
  const fetchedAt = new Date(nowMs).toISOString();
  return videos
    .filter((v) => {
      const age = (nowMs - Date.parse(v.published_at)) / 3600_000;
      return age <= youtubeConfig.maxAgeHours && age >= -0.1 && !isRecommendation(v.title) &&
        !looksLikeInstructions(v.title);
    })
    .map((v) => ({
      video_id: v.video_id,
      channel_id: channel.channel_id,
      title: v.title.slice(0, 300),
      published_at: v.published_at,
      lang: channel.lang,
      topic_ids: assignTopics(v.title, topics),
      region: channel.region,
      fetched_at: fetchedAt,
    }));
}

export type PlaylistResult =
  | { ok: true; videos: PlaylistVideo[] }
  | { ok: false; quota: boolean };

/// Lee las últimas subidas de un canal. Nunca lanza y nunca deja la clave en un
/// mensaje. `quota` = la cuota diaria se agotó (se corta toda la corrida).
export async function fetchPlaylist(
  deps: Pick<Deps, "fetch">,
  apiKey: string,
  playlistId: string,
): Promise<PlaylistResult> {
  const url = new URL(youtubeConfig.url);
  url.searchParams.set("part", "snippet,contentDetails");
  url.searchParams.set("maxResults", String(youtubeConfig.maxResults));
  url.searchParams.set("playlistId", playlistId);
  url.searchParams.set("key", apiKey);
  try {
    const res = await deps.fetch(url.toString(), { signal: AbortSignal.timeout(youtubeConfig.timeoutMs) });
    if (!res.ok) {
      const text = await res.text();
      const quota = res.status === 403 && /quotaExceeded|rateLimitExceeded/.test(text);
      // Solo el estado: el cuerpo podría repetir la clave.
      console.error("[news-warm] youtube", res.status, quota ? "quota" : "");
      return { ok: false, quota };
    }
    return { ok: true, videos: parsePlaylistItems(await res.json()) };
  } catch (e) {
    console.error("[news-warm] youtube fetch", e instanceof Error ? e.name : "error");
    return { ok: false, quota: false };
  }
}

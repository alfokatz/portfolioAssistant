// Verifica los canales de YouTube propuestos por compliance y arma el SQL para
// cargarlos en `video_channel_allowlist` (revisión
// docs/legal/reviews/2026-11-21-brief-diario-medios-y-youtube.md §2).
//
// Nadie inventa un `channel_id`: cada candidato se resuelve contra la API
// (`channels.list`, 1 unidad de cuota por canal) por su handle o id, y el SQL
// solo incluye los que devuelven un canal cuyo título coincide con el esperado.
// El reporte (por stderr) muestra título, handle, suscriptores y el link para
// que una persona confirme que es el canal oficial del medio antes de correr
// el SQL.
//
//   YOUTUBE_API_KEY=<clave> deno run -A scripts/youtube_channels.ts > /tmp/channels.sql
//   YOUTUBE_API_KEY=<clave> deno run -A scripts/youtube_channels.ts --all   # incluye prioridad 2
//
// Después: revisar el reporte, abrir cada link, y correr /tmp/channels.sql en
// el SQL editor de Supabase. Es idempotente (on conflict do update).
//
// La clave va en la URL de la API: el script nunca imprime la URL ni el cuerpo
// de un error.

export type Candidate = {
  name: string;
  /// Handle sin "@" o id `UC…`; se prueban en orden hasta que uno resuelva.
  lookups: string[];
  /// Texto que tiene que aparecer en el título del canal (sin mayúsculas).
  expectTitle: string;
  lang: "es" | "en";
  region: "global" | "us" | "eu" | "latam" | "asia";
  /// Noticias generales: un video sin tema se descarta (compliance H3).
  requireTopic: boolean;
  /// Medio en `news_source_allowlist`; solo se usa si está habilitado.
  outletDomain?: string;
  priority: 1 | 2;
};

export const candidates: Candidate[] = [
  // Prioridad 1 (§2.3).
  { name: "Reuters", lookups: ["Reuters"], expectTitle: "reuters", lang: "en", region: "global", requireTopic: true, outletDomain: "reuters.com", priority: 1 },
  { name: "Bloomberg Television", lookups: ["UCIALMKvObZNtJ6AmdCLP7Lg", "markets", "BloombergTelevision"], expectTitle: "bloomberg", lang: "en", region: "global", requireTopic: false, outletDomain: "bloomberg.com", priority: 1 },
  { name: "CNBC", lookups: ["UCvJJ_dzjViJCoLf5uKUTwoA", "CNBC"], expectTitle: "cnbc", lang: "en", region: "us", requireTopic: false, outletDomain: "cnbc.com", priority: 1 },
  { name: "CNBC Television", lookups: ["CNBCtelevision"], expectTitle: "cnbc television", lang: "en", region: "us", requireTopic: false, outletDomain: "cnbc.com", priority: 1 },
  { name: "Yahoo Finance", lookups: ["UCEAZeUIeJs0IjQiqTCdVSIg", "YahooFinance"], expectTitle: "yahoo finance", lang: "en", region: "us", requireTopic: false, outletDomain: "finance.yahoo.com", priority: 1 },
  { name: "The Wall Street Journal", lookups: ["wsj"], expectTitle: "wall street journal", lang: "en", region: "us", requireTopic: false, outletDomain: "wsj.com", priority: 1 },
  { name: "Financial Times", lookups: ["FinancialTimes"], expectTitle: "financial times", lang: "en", region: "eu", requireTopic: false, outletDomain: "ft.com", priority: 1 },
  { name: "The Economist", lookups: ["TheEconomist"], expectTitle: "economist", lang: "en", region: "global", requireTopic: false, outletDomain: "economist.com", priority: 1 },
  { name: "DW News", lookups: ["dwnews"], expectTitle: "dw news", lang: "en", region: "eu", requireTopic: true, outletDomain: "dw.com", priority: 1 },
  { name: "CNN en Español", lookups: ["cnnee", "CNNEE"], expectTitle: "cnn en español", lang: "es", region: "latam", requireTopic: true, outletDomain: "cnnespanol.cnn.com", priority: 1 },
  { name: "Bloomberg Línea", lookups: ["BloombergLinea"], expectTitle: "bloomberg l", lang: "es", region: "latam", requireTopic: false, outletDomain: "bloomberglinea.com", priority: 1 },
  { name: "DW Español", lookups: ["dwespanol"], expectTitle: "dw español", lang: "es", region: "latam", requireTopic: true, outletDomain: "dw.com", priority: 1 },
  // Prioridad 2: solo con --all.
  { name: "France 24 English", lookups: ["France24_en", "FRANCE24English"], expectTitle: "france 24", lang: "en", region: "eu", requireTopic: true, outletDomain: "france24.com", priority: 2 },
  { name: "France 24 Español", lookups: ["France24_es", "FRANCE24Espanol"], expectTitle: "france 24", lang: "es", region: "eu", requireTopic: true, outletDomain: "france24.com", priority: 2 },
  { name: "Euronews English", lookups: ["euronews"], expectTitle: "euronews", lang: "en", region: "eu", requireTopic: true, outletDomain: "euronews.com", priority: 2 },
  { name: "Euronews Español", lookups: ["euronewses"], expectTitle: "euronews", lang: "es", region: "eu", requireTopic: true, outletDomain: "euronews.com", priority: 2 },
  { name: "El Financiero", lookups: ["ElFinancieroMx", "ElFinanciero_Mx"], expectTitle: "el financiero", lang: "es", region: "latam", requireTopic: false, outletDomain: "elfinanciero.com.mx", priority: 2 },
  { name: "El País", lookups: ["elpais"], expectTitle: "el país", lang: "es", region: "eu", requireTopic: true, outletDomain: "elpais.com", priority: 2 },
];

export type ResolvedChannel = {
  candidate: Candidate;
  channelId: string;
  uploadsPlaylistId: string;
  title: string;
  handle: string | null;
  subscribers: number | null;
};

export type Resolution =
  | { ok: true; channel: ResolvedChannel }
  | { ok: false; candidate: Candidate; reason: string };

const channelIdPattern = /^UC[A-Za-z0-9_-]{22}$/;
const apiUrl = "https://www.googleapis.com/youtube/v3/channels";

type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

/// Resuelve un candidato probando sus lookups en orden. Nunca lanza.
export async function resolveCandidate(c: Candidate, apiKey: string, fetchFn: Fetch): Promise<Resolution> {
  const seen: string[] = [];
  for (const lookup of c.lookups) {
    const params = new URLSearchParams({ part: "id,snippet,contentDetails,statistics", key: apiKey });
    if (channelIdPattern.test(lookup)) params.set("id", lookup);
    else params.set("forHandle", `@${lookup.replace(/^@/, "")}`);
    let body: unknown;
    try {
      const res = await fetchFn(`${apiUrl}?${params}`, { signal: AbortSignal.timeout(10_000) });
      if (!res.ok) {
        seen.push(`${lookup}: HTTP ${res.status}`);
        await res.body?.cancel();
        continue;
      }
      body = await res.json();
    } catch {
      seen.push(`${lookup}: sin respuesta`);
      continue;
    }
    // deno-lint-ignore no-explicit-any
    const item = (body as any)?.items?.[0];
    if (!item) {
      seen.push(`${lookup}: no existe`);
      continue;
    }
    const id = String(item.id ?? "");
    const uploads = String(item.contentDetails?.relatedPlaylists?.uploads ?? "");
    const title = String(item.snippet?.title ?? "");
    if (!channelIdPattern.test(id) || !uploads) {
      seen.push(`${lookup}: respuesta incompleta`);
      continue;
    }
    if (!title.toLowerCase().includes(c.expectTitle)) {
      seen.push(`${lookup}: el título "${title}" no coincide con "${c.expectTitle}"`);
      continue;
    }
    const subs = Number(item.statistics?.subscriberCount);
    return {
      ok: true,
      channel: {
        candidate: c,
        channelId: id,
        uploadsPlaylistId: uploads,
        title,
        handle: typeof item.snippet?.customUrl === "string" ? item.snippet.customUrl : null,
        subscribers: Number.isFinite(subs) ? subs : null,
      },
    };
  }
  return { ok: false, candidate: c, reason: seen.join("; ") || "sin lookups" };
}

const lit = (s: string) => `'${s.replaceAll("'", "''")}'`;

/// SQL idempotente. `outlet_domain` solo si el medio está habilitado (si no,
/// queda null y la FK no se rompe).
export function toSql(channels: ResolvedChannel[]): string {
  if (channels.length === 0) return "-- Ningún canal verificado: no hay nada para cargar.\n";
  const rows = channels.map((ch) => {
    const c = ch.candidate;
    const outlet = c.outletDomain
      ? `(select domain from public.news_source_allowlist where domain = ${lit(c.outletDomain)} and enabled)`
      : "null";
    return `  (${lit(ch.channelId)}, ${lit(ch.uploadsPlaylistId)}, ${lit(c.name)}, ${outlet}, ${lit(c.lang)}, ${lit(c.region)}, ${c.requireTopic}, true)`;
  });
  return [
    "-- Canales de YouTube verificados con channels.list (scripts/youtube_channels.ts).",
    "-- Revisar el reporte y abrir cada link antes de correrlo.",
    "insert into public.video_channel_allowlist",
    "  (channel_id, uploads_playlist_id, name, outlet_domain, lang, region, require_topic, enabled)",
    "values",
    rows.join(",\n"),
    "on conflict (channel_id) do update set",
    "  uploads_playlist_id = excluded.uploads_playlist_id,",
    "  name = excluded.name,",
    "  outlet_domain = excluded.outlet_domain,",
    "  lang = excluded.lang,",
    "  region = excluded.region,",
    "  require_topic = excluded.require_topic,",
    "  enabled = excluded.enabled;",
    "",
  ].join("\n");
}

export function report(results: Resolution[]): string {
  const lines = ["Canales verificados (abrí cada link y confirmá que es el oficial del medio):"];
  for (const r of results) {
    if (r.ok) {
      const ch = r.channel;
      const subs = ch.subscribers == null ? "?" : ch.subscribers.toLocaleString("es-AR");
      lines.push(
        `  ✓ ${ch.candidate.name}: "${ch.title}" ${ch.handle ?? ""} · ${subs} suscriptores · ` +
          `https://www.youtube.com/channel/${ch.channelId}` + (ch.candidate.requireTopic ? " · exige tema" : ""),
      );
    }
  }
  const failed = results.filter((r): r is Extract<Resolution, { ok: false }> => !r.ok);
  if (failed.length > 0) {
    lines.push("No verificados (no entran al SQL; buscá el link en el sitio del medio y agregalo a `lookups`):");
    for (const f of failed) lines.push(`  ✗ ${f.candidate.name}: ${f.reason}`);
  }
  return lines.join("\n") + "\n";
}

if (import.meta.main) {
  const apiKey = Deno.env.get("YOUTUBE_API_KEY");
  if (!apiKey) {
    console.error("Falta YOUTUBE_API_KEY.");
    Deno.exit(1);
  }
  const all = Deno.args.includes("--all");
  const list = candidates.filter((c) => all || c.priority === 1);
  const results: Resolution[] = [];
  for (const c of list) results.push(await resolveCandidate(c, apiKey, fetch));
  console.error(report(results));
  console.log(toSql(results.flatMap((r) => (r.ok ? [r.channel] : []))));
}

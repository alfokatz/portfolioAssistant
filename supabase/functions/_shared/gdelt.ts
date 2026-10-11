// GDELT DOC 2.0 (api.gdeltproject.org): titulares de medios de todo el
// mundo, gratis citando la fuente. Solo se usa título, medio, fecha y link
// (nunca el texto ni la `socialimage`, que tienen derechos de autor).
//
// GDELT pide "un pedido cada 5 segundos": el limitador es GLOBAL (tabla
// `upstream_rate_gate`, compartida por todas las instancias), con backoff
// ante 429, y casi todo sale de la caché compartida.

import type { Deps } from "./common.ts";
import { sleep } from "./common.ts";

export const gdeltConfig = {
  url: "https://api.gdeltproject.org/api/v2/doc/doc",
  minIntervalMs: 5_500,
  /// Cuánto espera un pedido su turno antes de rendirse (y servir caché):
  /// la tool del chat corta los titulares a los 10 s.
  maxWaitMs: 7_000,
  timeoutMs: 15_000,
  /// Sin filtro de medios en la consulta (GDELT rechaza consultas largas:
  /// "Your query was too short or too long" con 28 dominios): se piden más
  /// notas y se filtra contra la allowlist en el servidor.
  maxRecords: 250,
  /// Dominios dentro de la consulta. 0 = ninguno (filtro solo en el servidor).
  maxDomainsPerQuery: 0,
};

export class GdeltUnavailable extends Error {}

export type Headline = {
  title: string;
  url: string;
  source: string;
  domain: string;
  published_at: string;
  language: "es" | "en" | null;
};

/// "NVIDIA CORP" → "NVIDIA"; "Apple Inc." → "Apple": el nombre con el que
/// la prensa nombra a la empresa (GDELT busca por texto, no por ticker).
export function pressName(title: string): string {
  const cleaned = title
    .replace(/\s*\/[A-Z]{2}\/?$/, "")
    .replace(/[,.]/g, " ")
    .replace(
      /\b(inc|incorporated|corp|corporation|co|company|ltd|limited|plc|sa|s a|nv|n v|ag|se|holdings?|group|the|class [a-z]|adr|ads|de cv|sab|lp|llc)\b/gi,
      " ",
    )
    .replace(/\s+/g, " ")
    .trim();
  const base = cleaned || title.trim();
  // Todo en mayúsculas (como lo publica la SEC) → Capitalizado, salvo
  // siglas cortas (IBM, AMD, YPF).
  if (base === base.toUpperCase()) {
    return base.split(" ").map((w) => (w.length <= 4 ? w : w[0] + w.slice(1).toLowerCase())).join(" ");
  }
  return base;
}

/// Date → "YYYYMMDDHHMMSS" (UTC), el formato de startdatetime/enddatetime.
export const gdeltDate = (d: Date) => d.toISOString().replace(/[-:]/g, "").slice(0, 15).replace("T", "");

/// Consulta ArtList: el nombre de cada empresa (frase exacta si tiene
/// espacios, varias unidas con OR), medios permitidos y español o inglés.
/// Con [from]/[to] (informe semanal) usa fechas; si no, últimos 7 días.
export function gdeltUrl(
  names: string[],
  domains: string[],
  opts: { from?: Date; to?: Date } = {},
): string {
  const terms = names.map((n) => (n.includes(" ") ? `"${n}"` : n));
  const nameClause = terms.length > 1 ? `(${terms.join(" OR ")})` : terms[0];
  const inQuery = domains.slice(0, gdeltConfig.maxDomainsPerQuery);
  const domainClause = inQuery.length > 0
    ? ` (${inQuery.map((d) => `domain:${d}`).join(" OR ")})`
    : "";
  const params = new URLSearchParams({
    query: `${nameClause}${domainClause} (sourcelang:english OR sourcelang:spanish)`,
    mode: "ArtList",
    format: "json",
    sort: "DateDesc",
    maxrecords: String(gdeltConfig.maxRecords),
  });
  if (opts.from && opts.to) {
    params.set("startdatetime", gdeltDate(opts.from));
    params.set("enddatetime", gdeltDate(opts.to));
  } else {
    params.set("timespan", "7d");
  }
  return `${gdeltConfig.url}?${params}`;
}

const fold = (s: string) => s.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");

/// Reparte titulares por empresa: va con la que nombra en el título (con
/// una sola empresa en la consulta, todos son de ella).
export function assignByName(headlines: Headline[], names: Record<string, string>): Record<string, Headline[]> {
  const tickers = Object.keys(names);
  const out: Record<string, Headline[]> = Object.fromEntries(tickers.map((t) => [t, []]));
  for (const h of headlines) {
    if (tickers.length === 1) {
      out[tickers[0]].push(h);
      continue;
    }
    const title = fold(h.title);
    for (const t of tickers) {
      const name = fold(names[t]);
      const re = new RegExp(`(^|[^a-z0-9])(${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}|${t.toLowerCase()})([^a-z0-9]|$)`);
      if (re.test(title)) out[t].push(h);
    }
  }
  return out;
}

/// "20261010T143000Z" → ISO.
function parseSeenDate(s: string): string | null {
  const m = /^(\d{4})(\d{2})(\d{2})T?(\d{2})(\d{2})(\d{2})Z?$/.exec(s ?? "");
  return m ? `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}Z` : null;
}

const hostOf = (url: string) => {
  try {
    return new URL(url).hostname.replace(/^www\./, "").toLowerCase();
  } catch {
    return "";
  }
};

function allowedDomain(host: string, allow: Map<string, string>): string | null {
  for (const domain of allow.keys()) {
    if (host === domain || host.endsWith(`.${domain}`)) return domain;
  }
  return null;
}

/// Normaliza un título para detectar el mismo hecho en varios medios.
const titleKey = (t: string) =>
  t.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9 ]/g, " ")
    .split(/\s+/).filter((w) => w.length > 3).slice(0, 8).join(" ");

/// Respuesta de GDELT → titulares de medios permitidos, sin repetidos (misma
/// URL o mismo título), el más nuevo primero. Nunca la `socialimage`.
// deno-lint-ignore no-explicit-any
export function parseArticles(json: any, allow: Map<string, string>): Headline[] {
  const list = Array.isArray(json?.articles) ? json.articles : [];
  const seenUrl = new Set<string>();
  const seenTitle = new Set<string>();
  const out: Headline[] = [];
  for (const a of list) {
    const url = typeof a?.url === "string" ? a.url : "";
    const title = typeof a?.title === "string" ? a.title.replace(/\s+/g, " ").trim() : "";
    const published = parseSeenDate(String(a?.seendate ?? ""));
    if (!url.startsWith("https://") && !url.startsWith("http://")) continue;
    if (!title || !published) continue;
    const domain = allowedDomain(hostOf(url), allow);
    if (!domain) continue;
    const key = titleKey(title);
    if (seenUrl.has(url) || (key && seenTitle.has(key))) continue;
    seenUrl.add(url);
    if (key) seenTitle.add(key);
    const lang = String(a?.language ?? "").toLowerCase();
    out.push({
      title,
      url,
      source: allow.get(domain)!,
      domain,
      published_at: published,
      language: lang.startsWith("span") ? "es" : lang.startsWith("eng") ? "en" : null,
    });
  }
  return out.sort((x, y) => y.published_at.localeCompare(x.published_at));
}

/// Pide el turno global de GDELT (esperando hasta [maxWaitMs]) y consulta.
/// Un 429 corre el turno y se reintenta una vez.
export async function gdeltFetch(
  deps: Pick<Deps, "db" | "fetch">,
  url: string,
  maxWaitMs = gdeltConfig.maxWaitMs,
): Promise<unknown> {
  const deadline = Date.now() + maxWaitMs;
  for (let attempt = 0; attempt < 2; attempt++) {
    for (;;) {
      const { data } = await deps.db.rpc("upstream_rate_take", {
        p_source: "gdelt",
        p_interval_ms: gdeltConfig.minIntervalMs,
      });
      if (data === true) break;
      if (Date.now() + 1_000 > deadline) throw new GdeltUnavailable("rate gate busy");
      await sleep(1_000);
    }
    let res: Response;
    try {
      res = await deps.fetch(url, { signal: AbortSignal.timeout(gdeltConfig.timeoutMs) });
    } catch (e) {
      throw new GdeltUnavailable(`fetch failed: ${e}`);
    }
    if (res.status === 429) {
      await res.body?.cancel();
      continue;
    }
    if (res.status !== 200) {
      await res.body?.cancel();
      throw new GdeltUnavailable(`http ${res.status}`);
    }
    const text = await res.text();
    // Sin resultados GDELT responde `{}`; con una consulta inválida, texto.
    if (!text.trim().startsWith("{")) throw new GdeltUnavailable(`not json: ${text.slice(0, 120)}`);
    return JSON.parse(text);
  }
  throw new GdeltUnavailable("rate limited");
}

export async function newsAllowlist(deps: Pick<Deps, "db">): Promise<Map<string, string>> {
  const { data } = await deps.db.from("news_source_allowlist").select("domain, name").eq("enabled", true);
  return new Map((data ?? []).map((r: { domain: string; name: string }) => [r.domain, r.name]));
}

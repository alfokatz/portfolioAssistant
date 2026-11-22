// Fuentes de respaldo de titulares por ticker (brief diario / feed), para
// cuando GDELT falla, tiene límite de pedidos o no trae nada reciente:
//
//   1. Finnhub `/company-news` (misma clave `FINNHUB_API_KEY` y mismo secreto
//      que el proxy `finnhub`): solo tickers de EE. UU. (CEDEAR y ADR
//      incluidos: MELI, GGAL, YPF cotizan allá).
//   2. Yahoo Finance `v1/finance/search` (`news`): cualquier símbolo (.BA,
//      cripto, bonos), con la sesión que ya arma `yahoo_session.ts`.
//
// Mismas reglas que GDELT: solo medios de `news_source_allowlist` (por el
// dominio del link o, si el link es un redirect del proveedor, por el NOMBRE
// del medio), sin duplicados, y de cada nota solo título, medio, fecha, link
// e `image_url` (la URL https; nunca se descarga ni se guarda la imagen).
// Nunca lanzan: devuelven `status` para distinguir "no hay" de "no se pudo".

import type { Deps } from "./common.ts";
import type { Headline } from "./gdelt.ts";
import { getSession, yahooSessionConfig } from "./yahoo_session.ts";

/// Finnhub free y Yahoo no permiten uso comercial (compliance 22/11,
/// docs/legal/reviews/2026-11-22-noticias-fotos-y-fuentes.md; runbook
/// news-sources-v2). Quedan apagados salvo que el secreto
/// NEWS_FALLBACK_LICENSED=1 confirme una licencia escrita.
export const fallbackLicensed = (env: (k: string) => string | undefined) =>
  env("NEWS_FALLBACK_LICENSED") === "1";

export const fallbackConfig = {
  finnhubUrl: "https://finnhub.io/api/v1/company-news",
  yahooSearchUrl: "https://query2.finance.yahoo.com/v1/finance/search",
  timeoutMs: 6_000,
  /// Cuántas notas de la respuesta se miran (Finnhub devuelve cientos).
  maxScanned: 60,
  windowDays: 2,
};

/// `ok` = la fuente respondió (aunque sin notas); `failed` = error de red,
/// 429 o 5xx; `skipped` = no aplica (sin clave, ticker no estadounidense).
export type FallbackResult = { status: "ok" | "failed" | "skipped"; items: Headline[] };

const fold = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();

/// Solo https, con host y sin credenciales; hasta 500 caracteres. null si no
/// sirve. La app la usa tal cual para `Image.network`.
export function safeImageUrl(raw: unknown): string | null {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 500) return null;
  try {
    const u = new URL(raw.trim());
    if (u.protocol !== "https:" || !u.hostname.includes(".") || u.username || u.password) return null;
    return u.toString();
  } catch {
    return null;
  }
}

const hostOf = (url: string) => {
  try {
    return new URL(url).hostname.replace(/^www\./, "").toLowerCase();
  } catch {
    return "";
  }
};

/// Dominio permitido de una nota: el del link si está en la allowlist; si el
/// link es un redirect del proveedor (finnhub.io/api/news?id=…), el del medio
/// cuyo nombre es el `publisher` (igual, o "Yahoo" → "Yahoo Finance").
export function allowedDomainFor(url: string, publisher: string, allow: Map<string, string>): string | null {
  const host = hostOf(url);
  for (const d of allow.keys()) if (host === d || host.endsWith(`.${d}`)) return d;
  const p = fold(publisher);
  if (p.length < 2) return null;
  for (const [d, name] of allow) {
    const n = fold(name);
    if (n === p || n.startsWith(`${p} `)) return d;
  }
  return null;
}

const isHttp = (u: string) => u.startsWith("https://") || u.startsWith("http://");

const unixToIso = (s: unknown): string | null => {
  const n = typeof s === "number" ? s : Number(s);
  return Number.isFinite(n) && n > 1e9 ? new Date(n * 1000).toISOString() : null;
};

/// Finnhub: `[{headline, source, url, datetime, image, ...}]` → titulares.
// deno-lint-ignore no-explicit-any
export function parseFinnhubNews(json: any, allow: Map<string, string>): Headline[] {
  const list = Array.isArray(json) ? json.slice(0, fallbackConfig.maxScanned) : [];
  const out: Headline[] = [];
  for (const a of list) {
    const url = typeof a?.url === "string" ? a.url : "";
    const title = typeof a?.headline === "string" ? a.headline.replace(/\s+/g, " ").trim() : "";
    const published = unixToIso(a?.datetime);
    if (!isHttp(url) || !title || !published) continue;
    const domain = allowedDomainFor(url, String(a?.source ?? ""), allow);
    if (!domain) continue;
    out.push({
      title, url, source: allow.get(domain)!, domain, published_at: published, language: "en",
      image_url: safeImageUrl(a?.image),
    });
  }
  return out;
}

/// Yahoo `search`: `{news: [{title, publisher, link, providerPublishTime,
/// thumbnail, relatedTickers}]}`. Con `relatedTickers`, la nota tiene que
/// nombrar al símbolo (Yahoo mezcla notas generales de mercado).
// deno-lint-ignore no-explicit-any
export function parseYahooNews(json: any, allow: Map<string, string>, symbol: string): Headline[] {
  const list = Array.isArray(json?.news) ? json.news.slice(0, fallbackConfig.maxScanned) : [];
  const out: Headline[] = [];
  for (const a of list) {
    const url = typeof a?.link === "string" ? a.link : "";
    const title = typeof a?.title === "string" ? a.title.replace(/\s+/g, " ").trim() : "";
    const published = unixToIso(a?.providerPublishTime);
    if (!isHttp(url) || !title || !published) continue;
    const related: unknown[] = Array.isArray(a?.relatedTickers) ? a.relatedTickers : [];
    if (related.length > 0 && !related.some((t) => String(t).toUpperCase() === symbol.toUpperCase())) continue;
    const domain = allowedDomainFor(url, String(a?.publisher ?? ""), allow);
    if (!domain) continue;
    out.push({
      title, url, source: allow.get(domain)!, domain, published_at: published, language: null,
      image_url: yahooThumbnail(a?.thumbnail),
    });
  }
  return out;
}

// deno-lint-ignore no-explicit-any
function yahooThumbnail(t: any): string | null {
  const res: { url?: unknown; width?: unknown }[] = Array.isArray(t?.resolutions) ? t.resolutions : [];
  // La más grande que no sea enorme; si no, la primera válida.
  const sorted = res.map((r) => ({ url: safeImageUrl(r?.url), w: Number(r?.width) || 0 }))
    .filter((r): r is { url: string; w: number } => r.url !== null)
    .sort((a, b) => b.w - a.w);
  return (sorted.find((r) => r.w <= 1000) ?? sorted[0])?.url ?? null;
}

/// Misma nota (URL o título normalizado) una sola vez, la más nueva primero.
export function dedupeHeadlines(list: Headline[]): Headline[] {
  const key = (t: string) =>
    fold(t).replace(/[^a-z0-9 ]/g, " ").split(/\s+/).filter((w) => w.length > 3).slice(0, 8).join(" ");
  const seenUrl = new Set<string>();
  const seenTitle = new Set<string>();
  const out: Headline[] = [];
  for (const h of [...list].sort((a, b) => b.published_at.localeCompare(a.published_at))) {
    const k = key(h.title);
    if (seenUrl.has(h.url) || (k && seenTitle.has(k))) continue;
    seenUrl.add(h.url);
    if (k) seenTitle.add(k);
    out.push(h);
  }
  return out;
}

/// Símbolo de EE. UU. "plano" (AAPL, BRK-B): lo único que Finnhub company-news
/// cubre bien. Sin sufijo de bolsa ni cripto.
export const isUsPlainSymbol = (symbol: string) => /^[A-Z]{1,5}([.-][AB])?$/.test(symbol.toUpperCase());

const ymd = (ms: number) => new Date(ms).toISOString().slice(0, 10);

type FallbackDeps = Pick<Deps, "fetch" | "env" | "now">;

export async function finnhubNews(
  deps: FallbackDeps, symbol: string, allow: Map<string, string>,
): Promise<FallbackResult> {
  const token = deps.env("FINNHUB_API_KEY");
  if (!token || !isUsPlainSymbol(symbol)) return { status: "skipped", items: [] };
  const url = new URL(fallbackConfig.finnhubUrl);
  url.searchParams.set("symbol", symbol.toUpperCase().replace("-", "."));
  url.searchParams.set("from", ymd(deps.now() - fallbackConfig.windowDays * 86400_000));
  url.searchParams.set("to", ymd(deps.now()));
  url.searchParams.set("token", token);
  try {
    const res = await deps.fetch(url.toString(), { signal: AbortSignal.timeout(fallbackConfig.timeoutMs) });
    if (res.status !== 200) {
      await res.body?.cancel();
      return { status: "failed", items: [] };
    }
    return { status: "ok", items: parseFinnhubNews(await res.json(), allow) };
  } catch {
    return { status: "failed", items: [] };
  }
}

export async function yahooNews(
  deps: FallbackDeps, symbol: string, allow: Map<string, string>,
): Promise<FallbackResult> {
  try {
    const session = await getSession(deps);
    const url = new URL(fallbackConfig.yahooSearchUrl);
    url.searchParams.set("q", symbol);
    url.searchParams.set("quotesCount", "0");
    url.searchParams.set("newsCount", "15");
    if (session) url.searchParams.set("crumb", session.crumb);
    const res = await deps.fetch(url.toString(), {
      signal: AbortSignal.timeout(fallbackConfig.timeoutMs),
      headers: {
        "User-Agent": yahooSessionConfig.userAgent,
        Accept: "application/json",
        ...(session ? { Cookie: session.cookie } : {}),
      },
    });
    if (res.status !== 200) {
      await res.body?.cancel();
      return { status: "failed", items: [] };
    }
    return { status: "ok", items: parseYahooNews(await res.json(), allow, symbol) };
  } catch {
    return { status: "failed", items: [] };
  }
}

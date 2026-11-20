// Citas de la búsqueda web (Responses API) y costo de una búsqueda:
// compartido por `news-context`, `daily-brief` / `news-warm` (digests) y
// `news-compare`. Antes vivía en `news-context/handler.ts`, que lo re-exporta.

import type { ResponsesOutput } from "./openai_responses.ts";

export const citationConfig = {
  /// Modelo por default de las búsquedas web (override: NEWS_CONTEXT_MODEL).
  defaultModel: "gpt-5-mini",
  maxCitations: 8,
  /// US$ por búsqueda (developers.openai.com/api/docs/pricing, 2026-10).
  searchCallUsd: 0.01,
  /// US$ por millón de tokens [entrada, salida]; lo desconocido usa el default.
  tokenPrices: {
    "gpt-4.1-mini": [0.4, 1.6],
    "gpt-4.1": [2, 8],
    "gpt-5-mini": [0.25, 2],
    "gpt-5": [1.25, 10],
    "gpt-6-luna": [0.1, 0.5],
  } as Record<string, [number, number]>,
};

export type Citation = { title: string; url: string; source: string; domain: string };

export const hostOf = (url: string) => {
  try {
    return new URL(url).hostname.replace(/^www\./, "").toLowerCase();
  } catch {
    return "";
  }
};

/// El medio permitido al que pertenece [host] (subdominios incluidos).
export function allowedDomain(host: string, allow: Map<string, string>): string | null {
  for (const domain of allow.keys()) {
    if (host === domain || host.endsWith(`.${domain}`)) return domain;
  }
  return null;
}

/// Páginas de cotización o históricos de precios: no son una fuente de
/// noticias (`/equities/` y `-historical-data` son las de Investing).
const quotePage = /\/(quotes?|symbol|historical|history|equities)\b|-historical-data\b/i;

/// Hosts de prueba de un medio (visto: `www-stage-fastly.stellar.cnn.com`).
const stagingHost = /(^|[.-])(stage|staging|preview|dev|qa|fastly)([.-]|$)/i;

/// Una nota y no una portada o sección (`cnn.com/business`, `/markets/stocks`):
/// el último tramo de la ruta tiene guiones o números (el slug o el id de la
/// nota) o termina en .htm(l).
function looksLikeArticle(path: string): boolean {
  const last = path.split("/").filter((s) => s.length > 0).pop();
  return last !== undefined && (/[-_\d]/.test(last) || /\.html?$/i.test(last));
}

/// Un título legible a partir del slug de la nota
/// (`/2026/11/12/nvidia-ceo-jensen-huang-resigns.html` → "Nvidia ceo jensen
/// huang resigns"). null si la ruta no tiene un slug con palabras.
export function titleFromUrl(url: URL): string | null {
  const segments = url.pathname.split("/").filter((s) => s.length > 0).reverse();
  for (const seg of segments) {
    const words = decodeURIComponent(seg)
      .replace(/\.html?$/i, "")
      .split(/[-_]+/)
      // Fechas, ids y hashes del final no son palabras del título.
      .filter((w) => /[a-záéíóúñ]/i.test(w) && !/^[0-9a-f]{6,}$/i.test(w) && !/\d{3,}/.test(w));
    if (words.length >= 3) {
      const text = words.join(" ").toLowerCase();
      return text.charAt(0).toUpperCase() + text.slice(1);
    }
  }
  return null;
}

/// Si [url] es un artículo citable: de un host de producción, que no sea
/// una página de datos de mercado ni una portada o sección.
export function isArticleUrl(url: URL): boolean {
  return !stagingHost.test(url.hostname) && !quotePage.test(url.pathname) && looksLikeArticle(url.pathname);
}

/// Citas sin repetir, solo artículos ([isArticleUrl]) de medios permitidos, sin
/// parámetros de rastreo.
export function citationsOf(annotations: { url: string; title?: string }[], allow: Map<string, string>): Citation[] {
  const seen = new Set<string>();
  const out: Citation[] = [];
  for (const a of annotations) {
    let url: URL;
    try {
      url = new URL(a.url);
    } catch {
      continue;
    }
    for (const k of [...url.searchParams.keys()]) if (k.startsWith("utm_")) url.searchParams.delete(k);
    const clean = url.toString();
    const domain = allowedDomain(hostOf(clean), allow);
    if (!domain || seen.has(clean) || !isArticleUrl(url)) continue;
    seen.add(clean);
    const source = allow.get(domain)!;
    const given = (a.title ?? "").trim();
    // Sin título (o solo el nombre del medio), el de la URL: en la app la
    // nota se ve con algo que dice de qué trata, no "CNBC, CNBC, CNBC".
    const title = given && given.toLowerCase() !== source.toLowerCase() ? given : titleFromUrl(url) ?? source;
    out.push({ title, url: clean, source, domain });
    if (out.length === citationConfig.maxCitations) break;
  }
  return out;
}

export function costUsd(model: string, out: ResponsesOutput): number {
  const [inPrice, outPrice] = citationConfig.tokenPrices[model] ?? citationConfig.tokenPrices[citationConfig.defaultModel];
  const calls = Math.max(out.searchCalls, 1);
  return Number(
    (calls * citationConfig.searchCallUsd + (out.inputTokens * inPrice + out.outputTokens * outPrice) / 1e6).toFixed(6),
  );
}

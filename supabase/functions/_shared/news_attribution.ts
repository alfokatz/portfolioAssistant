// Validador de atribución, determinístico: convierte el texto con viñetas y
// las anotaciones (citas) de una búsqueda web en algo que se puede mostrar
// con medio y link, y descarta lo que no se puede respaldar. Lo usan los
// digests (`news_digest.ts`: pulso y temas) y `news-compare`.
//
// Spec: docs/superpowers/specs/2026-11-20-brief-diario-tech.md §3.5 y §3.6.
//
// Reglas (comparar fuentes):
// 1. Cada punto tiene al menos 1 anotación DENTRO de su rango de texto, de un
//    dominio de la allowlist, que sea una nota (`isArticleUrl`).
// 2. `agree` exige al menos 2 dominios distintos; con uno solo pasa a `only`.
// 3. El texto nombra al medio de cada cita; si no, se antepone "Según <medio>,"
//    o "According to <outlet>,".
// 4. Se descartan los puntos con consejo, con comillas o con cifras que no
//    estén en el título citado.
// 5. Con menos de 2 medios distintos en total: `insufficient_sources`.
//
// Un titular o una viñeta con texto del modelo NUNCA se muestra sin cita.

import { allowedDomain, citationsOf, hostOf } from "./news_citations.ts";
import { isRecommendation } from "./recommendation.ts";

export type Annotation = { url: string; title?: string; start?: number; end?: number };
export type Allow = Map<string, string>;
export type Lang = "es" | "en";

/// Cita lista para mostrar.
export type Cite = { title: string; url: string; source: string; domain: string };

/// Consejo de comprar, vender o mantener (es/en), además de `isRecommendation`.
const advicePatterns: RegExp[] = [
  /\b(you should|you must|we recommend|i recommend|consider (buying|selling|holding))\b/i,
  /\b(buy|sell|hold)\s+(it|them|now|today|this|these|more|the dip|shares|stock|stocks)\b/i,
  /\b(strong|top|best)\s+(buy|sell)\b/i,
  /\b(deber[ií]as|te recomendamos|te recomiendo|conviene|es momento de|momento de)\s+(comprar|vender|mantener)\b/i,
  /\b(comprar|vender|mantener)\s+(ahora|hoy|ya|m[aá]s|acciones|la acci[oó]n)\b/i,
  /\b(compr[aá]|vend[eé]|mantené|aprovech[aá])\b/i,
];

/// true si el texto da un consejo de inversión al lector.
export function isAdvice(text: string): boolean {
  return isRecommendation(text) || advicePatterns.some((r) => r.test(text));
}

/// Comillas (texto copiado de un artículo): rectas dobles y tipográficas. El
/// apóstrofe (`Barron's`) no cuenta.
const quoteMarks = /["“”«»„‟]/;
export const hasQuotes = (text: string) => quoteMarks.test(text);

/// Titulares o viñetas que intentan darle órdenes al modelo ("ignore previous
/// instructions…"). Misma regex que `WeeklyReportInputBuilder.looksLikeInstructions`
/// (lib/features/weekly_report/data/weekly_report_input_builder.dart): si
/// cambia una, cambia la otra.
const injectionPattern = new RegExp(
  "ignore\\s+(all\\s+|any\\s+|the\\s+)?(previous|prior|above)|" +
    "disregard\\s+(all\\s+|the\\s+)?(previous|prior|above)|" +
    "system\\s+prompt|you\\s+are\\s+now|new\\s+instructions|" +
    "ignor[aá]\\s+(las\\s+)?instrucciones|olvid[aá]\\s+(las\\s+)?instrucciones",
  "i",
);
export const looksLikeInstructions = (text: string) => injectionPattern.test(text);

const fold = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");

const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/// ¿[text] nombra a [name] como palabra entera (sin tildes ni mayúsculas)?
export function mentions(text: string, name: string): boolean {
  const n = fold(name).trim();
  if (!n) return false;
  return new RegExp(`(^|[^a-z0-9])${escapeRe(n)}([^a-z0-9]|$)`).test(fold(text));
}

// ---------------------------------------------------------------------------
// Viñetas con su rango en el texto original
// ---------------------------------------------------------------------------

export type Bullet = {
  /// Texto limpio (sin marcador, negritas ni citas en línea).
  text: string;
  /// Rango [start, end) de la línea en el texto original (para ubicar citas).
  start: number;
  end: number;
  /// Etiqueta opcional que pide el prompt de comparar fuentes.
  tag: "agree" | "differ" | "only" | null;
};

const bulletMark = /^(?:[-•*–—]|\d{1,2}[.)])\s+/;
const tagMark = /^\**\[?\s*(agree|differ|only)\s*\]?\**\s*[:\-–—]?\s*/i;

/// Limpia una línea: marcador de viñeta, negritas y citas en línea
/// "([medio](url))" que el modelo a veces deja (las citas van aparte).
export function cleanLine(line: string): string {
  return line
    .replace(bulletMark, "")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\s*\(\[[^\]]*\]\([^)]*\)\)/g, "")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

/// Las viñetas del texto, cada una con su rango. Con "SIN_NOVEDADES" (la señal
/// de que no hay nada) no hay viñetas. Sin ninguna viñeta marcada (el modelo
/// contestó en párrafos), cada párrafo es una.
export function bulletsWithSpans(text: string, max = 8): Bullet[] {
  if (text.trim().startsWith("SIN_NOVEDADES")) return [];
  const lines: { raw: string; start: number; end: number }[] = [];
  let pos = 0;
  for (const raw of text.split("\n")) {
    const start = pos;
    pos += raw.length + 1;
    const trimmed = raw.trim();
    if (trimmed.length === 0) continue;
    lines.push({ raw: trimmed, start, end: start + raw.length });
  }
  const marked = lines.filter((l) => bulletMark.test(l.raw));
  const picked = marked.length > 0
    ? marked
    : lines.filter((l) => !l.raw.includes("SIN_NOVEDADES") && !l.raw.endsWith(":"));
  const out: Bullet[] = [];
  for (const l of picked) {
    let body = cleanLine(l.raw);
    let tag: Bullet["tag"] = null;
    const m = tagMark.exec(body);
    if (m) {
      tag = m[1].toLowerCase() as Bullet["tag"];
      body = body.slice(m[0].length).trim();
    }
    if (body.length === 0) continue;
    out.push({ text: body, start: l.start, end: l.end, tag });
  }
  return out.slice(0, max);
}

// ---------------------------------------------------------------------------
// Citas dentro del rango de una viñeta
// ---------------------------------------------------------------------------

/// Citas (de la allowlist, notas y no portadas, sin repetidos) cuya anotación
/// cae dentro del rango de [b]. Las anotaciones sin rango no se pueden
/// atribuir a una viñeta y no cuentan.
export function citesInRange(b: Pick<Bullet, "start" | "end">, annotations: Annotation[], allow: Allow): Cite[] {
  const inside = annotations.filter((a) =>
    a.start !== undefined && a.end !== undefined && a.start >= b.start && a.end <= b.end + 1
  );
  return citationsOf(inside, allow);
}

export type CitedBullet = { text: string; cites: Cite[] };

/// Viñetas con al menos 1 cita válida en su rango, sin consejo. Lo que no
/// tiene cita se descarta (digests).
export function citedBullets(
  text: string,
  annotations: Annotation[],
  allow: Allow,
  opts: { max?: number } = {},
): { kept: CitedBullet[]; dropped: { noCitation: number; advice: number } } {
  const kept: CitedBullet[] = [];
  const dropped = { noCitation: 0, advice: 0 };
  for (const b of bulletsWithSpans(text, 12)) {
    if (isAdvice(b.text) || looksLikeInstructions(b.text)) {
      dropped.advice++;
      continue;
    }
    const cites = citesInRange(b, annotations, allow);
    if (cites.length === 0) {
      dropped.noCitation++;
      continue;
    }
    kept.push({ text: b.text, cites });
    if (kept.length >= (opts.max ?? 4)) break;
  }
  return { kept, dropped };
}

// ---------------------------------------------------------------------------
// Comparar fuentes
// ---------------------------------------------------------------------------

export type ComparePointKind = "agree" | "differ" | "only";
export type ComparePoint = { kind: ComparePointKind; text: string; source_ids: string[] };
export type CompareSource = { title: string; source: string; domain: string; url: string };

export type Comparison = {
  status: "ok" | "insufficient_sources" | "empty";
  points: ComparePoint[];
  outlets: string[];
  sources: Record<string, CompareSource>;
};

/// Dígitos de cada número del texto ("4,1 %" → "41", "1.200" → "1200"), para
/// compararlos sin importar el separador decimal.
export function numbersOf(text: string): string[] {
  return (text.match(/\d[\d.,]*/g) ?? []).map((n) => n.replace(/[^\d]/g, "")).filter((n) => n.length > 0);
}

const prefixFor = (lang: Lang, outlets: string[]) => {
  const list = outlets.length <= 1
    ? outlets.join("")
    : `${outlets.slice(0, -1).join(", ")} ${lang === "en" ? "and" : "y"} ${outlets[outlets.length - 1]}`;
  return lang === "en" ? `According to ${list}, ` : `Según ${list}, `;
};

/// Baja la primera letra al anteponer "Según X," salvo siglas y nombres
/// propios en mayúsculas ("NVIDIA", "S&P").
function lowerFirst(text: string): string {
  if (text.length < 2) return text;
  const [a, b] = [text[0], text[1]];
  if (a === a.toUpperCase() && a !== a.toLowerCase() && b === b.toLowerCase()) return a.toLowerCase() + text.slice(1);
  return text;
}

/// Arma la comparación a partir del texto del modelo y sus anotaciones.
export function validateComparison(
  text: string,
  annotations: Annotation[],
  allow: Allow,
  lang: Lang,
): Comparison {
  const bullets = bulletsWithSpans(text, 10);
  if (bullets.length === 0) return { status: "empty", points: [], outlets: [], sources: {} };

  const sources: Record<string, CompareSource> = {};
  const idByUrl = new Map<string, string>();
  const idOf = (c: Cite) => {
    let id = idByUrl.get(c.url);
    if (!id) {
      id = `s${idByUrl.size + 1}`;
      idByUrl.set(c.url, id);
      sources[id] = { title: c.title, source: c.source, domain: c.domain, url: c.url };
    }
    return id;
  };

  const kept: { point: ComparePoint; outlets: string[] }[] = [];
  for (const b of bullets) {
    // 4. Consejo y comillas.
    if (isAdvice(b.text) || hasQuotes(b.text) || looksLikeInstructions(b.text)) continue;
    // 1. Citas dentro de su rango.
    const cites = citesInRange(b, annotations, allow);
    if (cites.length === 0) continue;
    const outlets = [...new Set(cites.map((c) => c.source))];
    // 4. Cifras que no están en los títulos citados.
    let bare = b.text;
    for (const o of outlets) bare = bare.replace(new RegExp(escapeRe(o), "gi"), " ");
    const titleNumbers = new Set(cites.flatMap((c) => numbersOf(c.title)));
    if (numbersOf(bare).some((n) => !titleNumbers.has(n))) continue;
    // 2. `agree` exige 2 dominios distintos.
    const domains = new Set(cites.map((c) => c.domain));
    let kind: ComparePointKind = b.tag ?? (domains.size >= 2 ? "agree" : "only");
    if (kind === "agree" && domains.size < 2) kind = "only";
    // 3. El texto nombra al medio de cada cita.
    const missing = outlets.filter((o) => !mentions(b.text, o));
    const pointText = missing.length > 0 ? prefixFor(lang, missing) + lowerFirst(b.text) : b.text;
    kept.push({ point: { kind, text: pointText, source_ids: cites.map(idOf) }, outlets });
  }

  const outlets = [...new Set(kept.flatMap((k) => k.outlets))];
  // 5. Menos de 2 medios distintos: no hay con qué comparar.
  if (outlets.length < 2) {
    const only = outlets.length === 1 ? outlets : [];
    return { status: "insufficient_sources", points: [], outlets: only, sources: {} };
  }
  return { status: "ok", points: kept.map((k) => k.point), outlets, sources };
}

export { allowedDomain, hostOf };

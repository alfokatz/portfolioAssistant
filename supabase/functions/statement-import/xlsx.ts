// Lector mínimo de Excel (.xlsx) sin dependencias: abre el zip con
// `DecompressionStream`, lee las hojas y las devuelve como texto separado
// por tabs para que siga por el lector de CSV (sin IA) o, si no tiene
// columnas reconocibles, por la IA como texto.
//
// No usa SheetJS: la versión de npm tiene fallas conocidas justamente al
// leer archivos de terceros, y la oficial no está en npm. Acá solo hace
// falta el valor de cada celda.
//
// .xls (el formato viejo, binario) no se lee: se pide guardarlo como .xlsx
// o CSV.

/// Topes contra archivos armados para inflarse (zip bomb).
export const xlsxLimits = {
  maxEntries: 5000,
  /// Lo que se descomprime de un solo archivo interno.
  maxEntryBytes: 20 * 1024 * 1024,
  /// Lo que se descomprime en total.
  maxTotalBytes: 40 * 1024 * 1024,
  maxSheets: 20,
};

export type Sheet = { name: string; text: string };

type ZipEntry = { name: string; method: number; compressedSize: number; size: number; offset: number };

const u16 = (b: Uint8Array, i: number) => b[i] | (b[i + 1] << 8);
const u32 = (b: Uint8Array, i: number) => (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0;

/// Las entradas del directorio central del zip. `null` si no es un zip
/// legible.
export function zipEntries(bytes: Uint8Array): ZipEntry[] | null {
  // El registro final está en los últimos 22 bytes + el comentario (hasta
  // 64 KB).
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 0xffff); i--) {
    if (u32(bytes, i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) return null;
  const count = u16(bytes, eocd + 10);
  let p = u32(bytes, eocd + 16);
  if (count > xlsxLimits.maxEntries) return null;
  const out: ZipEntry[] = [];
  const decoder = new TextDecoder();
  for (let n = 0; n < count; n++) {
    if (p + 46 > bytes.length || u32(bytes, p) !== 0x02014b50) return null;
    const nameLen = u16(bytes, p + 28);
    const extraLen = u16(bytes, p + 30);
    const commentLen = u16(bytes, p + 32);
    out.push({
      method: u16(bytes, p + 10),
      compressedSize: u32(bytes, p + 20),
      size: u32(bytes, p + 24),
      offset: u32(bytes, p + 42),
      name: decoder.decode(bytes.subarray(p + 46, p + 46 + nameLen)),
    });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

class TooLarge extends Error {}

/// Descomprime una entrada (guardada o deflate), cortando si se pasa de
/// [max] bytes.
async function inflate(bytes: Uint8Array, e: ZipEntry, max: number): Promise<Uint8Array> {
  const h = e.offset;
  if (h + 30 > bytes.length || u32(bytes, h) !== 0x04034b50) throw new Error("bad local header");
  const start = h + 30 + u16(bytes, h + 26) + u16(bytes, h + 28);
  const data = bytes.subarray(start, start + e.compressedSize);
  if (e.method === 0) {
    if (data.length > max) throw new TooLarge();
    return data;
  }
  if (e.method !== 8) throw new Error("unsupported compression");
  const stream = new Blob([data.slice()]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  const chunks: Uint8Array[] = [];
  let total = 0;
  for await (const chunk of stream) {
    total += chunk.length;
    if (total > max) throw new TooLarge();
    chunks.push(chunk);
  }
  const out = new Uint8Array(total);
  let o = 0;
  for (const c of chunks) {
    out.set(c, o);
    o += c.length;
  }
  return out;
}

const entities: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

export function unescapeXml(s: string): string {
  return s.replace(/&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);/g, (_, e: string) => {
    if (e[0] !== "#") return entities[e];
    const code = e[1] === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
    return Number.isFinite(code) && code <= 0x10ffff ? String.fromCodePoint(code) : "";
  });
}

function attr(tag: string, name: string): string | null {
  const m = tag.match(new RegExp(`\\s${name}="([^"]*)"`));
  return m ? unescapeXml(m[1]) : null;
}

/// El texto de un `<si>` o `<is>`: todos sus `<t>` (texto con formato
/// viene en varios pedazos).
function runText(xml: string): string {
  let s = "";
  for (const m of xml.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)) s += m[1];
  return unescapeXml(s);
}

export function sharedStrings(xml: string): string[] {
  return [...xml.matchAll(/<si>([\s\S]*?)<\/si>|<si\/>/g)].map((m) => (m[1] ? runText(m[1]) : ""));
}

/// Formatos de número de Excel que son fechas (los propios 14–22 y 45–47,
/// más los personalizados con d/m/y fuera de comillas y corchetes).
export function dateStyles(stylesXml: string): Set<number> {
  const custom = new Map<number, string>();
  for (const m of stylesXml.matchAll(/<numFmt\s[^>]*>/g)) {
    const id = Number(attr(m[0], "numFmtId"));
    const code = attr(m[0], "formatCode") ?? "";
    custom.set(id, code);
  }
  const isDateFmt = (id: number) => {
    if ((id >= 14 && id <= 22) || (id >= 45 && id <= 47)) return true;
    const code = custom.get(id);
    if (!code) return false;
    const bare = code.replace(/"[^"]*"|\[[^\]]*\]|\\./g, "");
    return /[dmy]/i.test(bare) && !/^[#0.,\s%]*$/.test(bare);
  };
  const out = new Set<number>();
  const xfs = stylesXml.match(/<cellXfs[^>]*>([\s\S]*?)<\/cellXfs>/);
  if (!xfs) return out;
  [...xfs[1].matchAll(/<xf\s[^>]*?\/?>/g)].forEach((m, i) => {
    if (isDateFmt(Number(attr(m[0], "numFmtId")))) out.add(i);
  });
  return out;
}

/// Número de serie de Excel → "YYYY-MM-DD".
export function serialToIso(serial: number, date1904 = false): string | null {
  if (!Number.isFinite(serial) || serial < 1) return null;
  const epoch = date1904 ? Date.UTC(1904, 0, 1) : Date.UTC(1899, 11, 30);
  const d = new Date(epoch + Math.floor(serial) * 86400000);
  const y = d.getUTCFullYear();
  if (y < 1970 || y > 2100) return null;
  return d.toISOString().slice(0, 10);
}

/// "BC12" → 54 (columna, desde 0).
export function columnIndex(ref: string): number {
  const letters = ref.match(/^[A-Z]+/)?.[0] ?? "";
  let n = 0;
  for (const ch of letters) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

/// Una celda lista para el texto con tabs: sin tabs ni saltos, y entre
/// comillas si tiene comillas (como lee `splitLine`).
function cellText(v: string): string {
  const s = v.replace(/[\t\r\n]+/g, " ").trim();
  return s.includes('"') ? `"${s.replace(/"/g, '""')}"` : s;
}

export function sheetText(xml: string, strings: string[], dates: Set<number>, date1904 = false): string {
  const lines: string[] = [];
  for (const row of xml.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
    const cells: string[] = [];
    let next = 0;
    for (const c of row[1].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const tag = `<c${c[1]}>`;
      const body = c[2] ?? "";
      const ref = attr(tag, "r");
      const col = ref ? columnIndex(ref) : next;
      if (col < 0 || col > 500) continue;
      next = col + 1;
      const type = attr(tag, "t");
      const raw = body.match(/<v>([\s\S]*?)<\/v>/)?.[1];
      let value = "";
      if (type === "s") value = strings[Number(raw)] ?? "";
      else if (type === "inlineStr") value = runText(body);
      else if (type === "str" || type === "e") value = raw ? unescapeXml(raw) : "";
      else if (type === "b") value = raw === "1" ? "TRUE" : "FALSE";
      else if (raw !== undefined) {
        const n = Number(raw);
        const style = Number(attr(tag, "s") ?? "0");
        value = dates.has(style) ? serialToIso(n, date1904) ?? raw : Number.isFinite(n) ? String(n) : raw;
      }
      while (cells.length < col) cells.push("");
      cells[col] = cellText(value);
    }
    if (cells.some((v) => v)) lines.push(cells.join("\t"));
  }
  return lines.join("\n");
}

/// Las hojas del libro, en orden, como texto con tabs. `null` si no es un
/// .xlsx legible o se pasa de los topes.
export async function readXlsx(bytes: Uint8Array): Promise<Sheet[] | null> {
  const entries = zipEntries(bytes);
  if (!entries) return null;
  const byName = new Map(entries.map((e) => [e.name.replace(/^\/+/, ""), e]));
  if (!byName.has("xl/workbook.xml")) return null;

  let budget = xlsxLimits.maxTotalBytes;
  const read = async (name: string): Promise<string | null> => {
    const e = byName.get(name);
    if (!e) return null;
    const data = await inflate(bytes, e, Math.min(xlsxLimits.maxEntryBytes, budget));
    budget -= data.length;
    // Algunos generadores (Open XML SDK) prefijan las etiquetas: `<x:row>`.
    return new TextDecoder().decode(data).replace(/<(\/?)[A-Za-z][\w.-]*:(?=[A-Za-z])/g, "<$1");
  };

  try {
    const workbook = (await read("xl/workbook.xml"))!;
    const rels = (await read("xl/_rels/workbook.xml.rels")) ?? "";
    const targets = new Map<string, string>();
    for (const m of rels.matchAll(/<Relationship\s[^>]*>/g)) {
      const id = attr(m[0], "Id");
      const target = attr(m[0], "Target");
      if (id && target) {
        targets.set(id, target.startsWith("/") ? target.slice(1) : `xl/${target}`.replace(/\/\.\//g, "/"));
      }
    }
    const date1904 = /<workbookPr\b[^>]*\sdate1904="(1|true)"/.test(workbook);
    const strings = sharedStrings((await read("xl/sharedStrings.xml")) ?? "");
    const dates = dateStyles((await read("xl/styles.xml")) ?? "");

    const sheets: Sheet[] = [];
    for (const m of workbook.matchAll(/<sheet\s[^>]*>/g)) {
      if (sheets.length >= xlsxLimits.maxSheets) break;
      const rid = attr(m[0], "r:id");
      const path = rid ? targets.get(rid) : undefined;
      if (!path) continue;
      const xml = await read(path);
      if (xml === null) continue;
      const text = sheetText(xml, strings, dates, date1904);
      if (text) sheets.push({ name: attr(m[0], "name") ?? "", text });
    }
    return sheets;
  } catch {
    // Zip roto, compresión rara o se pasó de los topes.
    return null;
  }
}

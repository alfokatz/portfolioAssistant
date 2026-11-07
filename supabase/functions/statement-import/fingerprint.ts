// Huella anónima del formato de un archivo de texto (CSV o una hoja de un
// .xlsx), para los logs: saber qué formatos no entiende el lector sin IA y
// cuáles conviene sumar. Nunca lleva contenido: el hash de los encabezados,
// cuántas columnas tiene y cuáles de ellas ya son conocidas. Puro salvo el
// hash.

import { detectDelimiter, normalizeHeader, splitLine, synonyms } from "./parse_csv.ts";

/// Palabras de columna que se pueden loguear tal cual (las que ya entiende
/// el lector y otras comunes de los exportes). Cualquier otra sale como "?":
/// una celda desconocida puede ser un dato del usuario.
const vocabulary = new Set([
  ...Object.values(synonyms).flat(),
  "account",
  "cuenta",
  "closeprice",
  "lastprice",
  "ultimoprecio",
  "marketvalue",
  "mktvalmarketvalue",
  "currentvalue",
  "value",
  "valor",
  "valuacion",
  "valorizacion",
  "gain",
  "gainloss",
  "unrealizedpl",
  "ganancia",
  "resultado",
  "variacion",
  "change",
  "type",
  "tipo",
  "assetcategory",
  "datadiscriminator",
  "mult",
  "code",
  "isin",
  "cusip",
  "header",
  "data",
]);

export type FormatFingerprint = {
  /// Primeros 12 hex del SHA-256 de los encabezados normalizados.
  hash: string;
  /// Columnas de la fila de encabezados.
  cols: number;
  /// Los encabezados con los desconocidos como "?" ("symbol|?|quantity").
  known: string;
};

/// La fila que parece de encabezados: entre las primeras 30, la de más
/// celdas no vacías sin números (los datos casi siempre tienen alguno).
export function headerRow(text: string): string[] | null {
  const lines = text.split(/\r\n|\n|\r/).filter((l) => l.trim()).slice(0, 30);
  if (lines.length === 0) return null;
  const delimiter = detectDelimiter(lines);
  let best: string[] | null = null;
  let bestCount = 1;
  for (const line of lines) {
    const cells = splitLine(line, delimiter).map(normalizeHeader);
    const filled = cells.filter((c) => c && !/\d/.test(c)).length;
    if (filled > bestCount) {
      best = cells;
      bestCount = filled;
    }
  }
  return best;
}

export async function fingerprint(text: string): Promise<FormatFingerprint | null> {
  const header = headerRow(text);
  if (!header) return null;
  const joined = header.join("|");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(joined));
  const hash = [...new Uint8Array(digest).slice(0, 6)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return {
    hash,
    cols: header.length,
    known: header.map((c) => (vocabulary.has(c) ? c : "?")).join("|").slice(0, 300),
  };
}

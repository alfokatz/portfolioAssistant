// Lector de CSV sin IA: si el archivo tiene una fila de encabezados con
// columnas reconocibles (ticker y cantidad como mínimo), las posiciones
// salen de acá sin cobrar una consulta. Puro.
//
// Entiende los exportes típicos de brókers en inglés y en español:
// separador `,` `;` tab o `|`, números con coma o punto decimal, fechas ISO,
// `dd/mm/yyyy`, `mm/dd/yyyy` y `yyyymmdd`. Los estados de cuenta por
// secciones de Interactive Brokers se leen por su sección de posiciones
// abiertas.

import { type ImportRow, type ImportWarning, isoDate, normalizeTicker } from "./rows.ts";

export type Field = "ticker" | "quantity" | "price" | "total_cost" | "date" | "currency" | "name";

/// Sinónimos de cada columna, en orden de preferencia (normalizados: sin
/// acentos, minúsculas, solo letras y números). Si dos columnas califican
/// para lo mismo, gana la de sinónimo más específico (el primero).
export const synonyms: Record<Field, string[]> = {
  ticker: [
    "symbol",
    "ticker",
    "simbolo",
    "tickersymbol",
    "instrumentsymbol",
    "securitysymbol",
    "especie",
    "codigo",
    "symbolcusip",
  ],
  quantity: [
    "quantity",
    "qty",
    "shares",
    "cantidad",
    "units",
    "unidades",
    "nominales",
    "titulos",
    "quantityheld",
    "sharesheld",
    "position",
    "cantidadnominal",
    "qtyquantity",
  ],
  price: [
    "averageprice",
    "avgprice",
    "averagecost",
    "avgcost",
    "averagecostpershare",
    "costbasispershare",
    "costpershare",
    "unitcost",
    "costprice",
    "purchaseprice",
    "openprice",
    "preciopromedio",
    "ppc",
    "preciodecompra",
    "preciocompra",
    "costopromedio",
    "costounitario",
    "averagecostbasis",
    "avgcostbasis",
    "price",
    "precio",
  ],
  total_cost: ["costbasis", "totalcost", "costbasistotal", "costototal", "montoinvertido", "invested", "cost"],
  date: [
    "purchasedate",
    "tradedate",
    "dateacquired",
    "acquired",
    "opendate",
    "fechadecompra",
    "fechacompra",
    "date",
    "fecha",
  ],
  currency: ["currency", "moneda", "ccy", "divisa"],
  name: ["description", "securityname", "name", "nombre", "descripcion", "security", "instrument", "instrumento"],
};

export function normalizeHeader(h: string): string {
  return h.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

/// "Price" o "Precio" a secas: en muchos brókers es el precio de hoy, no el
/// de compra.
const genericPrice = new Set(["price", "precio"]);

/// Columnas de valor de mercado: si están, "Price" es el precio de hoy.
const marketValue = new Set([
  "marketvalue",
  "mktvalmarketvalue",
  "currentvalue",
  "value",
  "valor",
  "valoractual",
  "valuacion",
  "valorizacion",
  "montovaluado",
]);

/// Separa una línea respetando comillas (RFC 4180 básico).
export function splitLine(line: string, delimiter: string): string[] {
  const out: string[] = [];
  let cur = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"') {
        if (line[i + 1] === '"') {
          cur += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        cur += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === delimiter) {
      out.push(cur.trim());
      cur = "";
    } else {
      cur += ch;
    }
  }
  out.push(cur.trim());
  return out;
}

/// El separador que da más columnas de forma consistente en las primeras
/// líneas.
export function detectDelimiter(lines: string[]): string {
  const sample = lines.slice(0, 30);
  let best = ",";
  let bestScore = -1;
  for (const d of [",", ";", "\t", "|"]) {
    const counts = sample.map((l) => splitLine(l, d).length).filter((n) => n > 1);
    if (counts.length === 0) continue;
    // Cuántas líneas comparten la cantidad de columnas más común.
    const freq = new Map<number, number>();
    for (const c of counts) freq.set(c, (freq.get(c) ?? 0) + 1);
    const [cols, times] = [...freq.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0])[0];
    const score = times * 100 + cols;
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return best;
}

/// A qué campo corresponde cada columna (índice → campo), o `null` si no
/// hay ticker y cantidad.
export function mapColumns(headers: string[]): Partial<Record<Field, number>> | null {
  const normalized = headers.map(normalizeHeader);
  const chosen: Partial<Record<Field, number>> = {};
  const used = new Set<number>();
  // Primero los campos con sinónimos más específicos, para que "price" no
  // se quede con "averageprice" antes que el campo correcto lo pida.
  const order: Field[] = ["ticker", "quantity", "price", "total_cost", "date", "currency", "name"];
  for (const field of order) {
    let bestIdx = -1;
    let bestRank = Infinity;
    normalized.forEach((h, idx) => {
      if (used.has(idx) || !h) return;
      const rank = synonyms[field].indexOf(h);
      if (rank >= 0 && rank < bestRank) {
        bestRank = rank;
        bestIdx = idx;
      }
    });
    if (bestIdx >= 0) {
      chosen[field] = bestIdx;
      used.add(bestIdx);
    }
  }
  if (chosen.ticker === undefined || chosen.quantity === undefined) return null;
  // "Price" a secas junto al costo total o al valor de mercado es el precio
  // de hoy: mejor sin precio (sale del costo total, o lo pide la app) que
  // tomar el de hoy como costo.
  if (
    chosen.price !== undefined && genericPrice.has(normalized[chosen.price]) &&
    (chosen.total_cost !== undefined || normalized.some((h) => marketValue.has(h)))
  ) {
    delete chosen.price;
  }
  return chosen;
}

/// Secciones de Interactive Brokers que traen las posiciones abiertas (en
/// inglés y en español).
const ibkrOpenPositions = new Set(["openpositions", "posicionesabiertas"]);

/// Lo que no es una acción, ETF, fondo o cripto (opciones, futuros, bonos,
/// divisas): no se importa.
const ibkrSkipCategory = /forex|divisa|option|opci[oó]n|future|futuro|bond|bono|warrant|cfd/i;

/// Un estado de cuenta de Interactive Brokers trae varias secciones en el
/// mismo CSV (`Sección,Header,...` y `Sección,Data,...`). Devuelve solo la
/// tabla de posiciones abiertas (una fila por símbolo), lista para el
/// lector común, o `null` si el archivo no tiene ese formato.
export function ibkrPositions(lines: string[], delimiter: string): { lines: string[]; skipped: number } | null {
  const split = lines.map((l) => splitLine(l, delimiter));
  const section = (r: string[]) => normalizeHeader(r[0] ?? "");
  const header = split.find((r) => r[1] === "Header" && ibkrOpenPositions.has(section(r)));
  if (!header) return null;
  const name = section(header);
  const cols = header.slice(2).map(normalizeHeader);
  const data = split.filter((r) => r[1] === "Data" && section(r) === name).map((r) => r.slice(2));
  // Con lotes, IBKR repite cada símbolo: "Summary" es el total por símbolo.
  const disc = cols.indexOf("datadiscriminator");
  const summaries = disc >= 0 ? data.filter((r) => r[disc] === "Summary") : [];
  const rows = summaries.length > 0 ? summaries : data;
  const category = cols.findIndex((c) => c === "assetcategory" || c === "categoriadeactivo");
  const symbol = cols.findIndex((c) => c === "symbol" || c === "simbolo");
  let skipped = 0;
  const kept: string[][] = [];
  for (const r of rows) {
    if (category >= 0 && ibkrSkipCategory.test(r[category] ?? "")) {
      skipped++;
      continue;
    }
    const out = [...r];
    // "BRK B" → "BRK-B" (clase de acción con espacio).
    if (symbol >= 0) out[symbol] = (out[symbol] ?? "").replace(/^([A-Z]{1,5}) ([A-Z])$/, "$1-$2");
    kept.push(out);
  }
  const quote = (v: string) => (v.includes(delimiter) || v.includes('"') ? `"${v.replace(/"/g, '""')}"` : v);
  return {
    lines: [header.slice(2), ...kept].map((r) => r.map(quote).join(delimiter)),
    skipped,
  };
}

/// Un número de un CSV: "$1,234.56", "1.234,56", "(12.5)", "1 234,5".
/// [commaDecimal]: el archivo usa coma decimal (separador `;`).
export function parseNumber(raw: string | undefined, commaDecimal: boolean): number | null {
  if (raw === undefined) return null;
  let s = raw.trim();
  if (!s || s === "-" || s === "--") return null;
  let negative = false;
  if (/^\(.*\)$/.test(s)) {
    negative = true;
    s = s.slice(1, -1);
  }
  s = s.replace(/[^\d.,\-]/g, "");
  if (s.startsWith("-")) {
    negative = !negative;
    s = s.slice(1);
  }
  if (!/\d/.test(s)) return null;
  const lastComma = s.lastIndexOf(",");
  const lastDot = s.lastIndexOf(".");
  if (lastComma >= 0 && lastDot >= 0) {
    // Los dos: el último es el decimal.
    s = lastComma > lastDot ? s.replace(/\./g, "").replace(",", ".") : s.replace(/,/g, "");
  } else if (lastComma >= 0) {
    const thousands = /^\d{1,3}(,\d{3})+$/.test(s);
    s = commaDecimal || !thousands ? s.replace(/,(?=[^,]*$)/, ".").replace(/,/g, "") : s.replace(/,/g, "");
  } else if (lastDot >= 0 && commaDecimal && /^\d{1,3}(\.\d{3})+$/.test(s)) {
    // "1.234" con coma decimal: es un separador de miles.
    s = s.replace(/\./g, "");
  }
  const n = Number(s);
  if (!Number.isFinite(n)) return null;
  return negative ? -n : n;
}

type DateParts = { a: number; b: number; year: number } | { iso: string };

function dateParts(raw: string): DateParts | null {
  const s = raw.trim();
  let m = s.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/);
  if (m) {
    const iso = isoDate(+m[1], +m[2], +m[3]);
    return iso ? { iso } : null;
  }
  m = s.match(/^(\d{4})(\d{2})(\d{2})(?:\b|$|;|,)/);
  if (m) {
    const iso = isoDate(+m[1], +m[2], +m[3]);
    return iso ? { iso } : null;
  }
  m = s.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})\b/);
  if (m) {
    const year = m[3].length === 2 ? 2000 + +m[3] : +m[3];
    return { a: +m[1], b: +m[2], year };
  }
  return null;
}

/// Día/mes o mes/día: si algún valor tiene el primer número mayor que 12
/// es día/mes; si es el segundo, mes/día. Si no se puede saber, día/mes
/// (la app es para Latinoamérica) y se avisa.
export function dateOrder(values: string[]): { order: "dmy" | "mdy"; ambiguous: boolean } {
  let dmy = false;
  let mdy = false;
  let any = false;
  for (const v of values) {
    const p = dateParts(v);
    if (!p || "iso" in p) continue;
    any = true;
    if (p.a > 12) dmy = true;
    if (p.b > 12) mdy = true;
  }
  if (dmy && !mdy) return { order: "dmy", ambiguous: false };
  if (mdy && !dmy) return { order: "mdy", ambiguous: false };
  return { order: "dmy", ambiguous: any };
}

export function parseDate(raw: string | undefined, order: "dmy" | "mdy"): string | null {
  if (!raw) return null;
  const p = dateParts(raw);
  if (!p) return null;
  if ("iso" in p) return p.iso;
  return order === "dmy" ? isoDate(p.year, p.b, p.a) : isoDate(p.year, p.a, p.b);
}

export type CsvResult = {
  rows: ImportRow[];
  warnings: ImportWarning[];
  /// Qué lector armó la tabla (para los logs).
  format: "generic" | "ibkr";
};

/// Las posiciones del CSV, o `null` si no tiene columnas reconocibles (la
/// importación sigue con la IA).
export function parseCsv(text: string): CsvResult | null {
  let lines = text.replace(/^﻿/, "").split(/\r\n|\n|\r/).filter((l) => l.trim().length > 0);
  if (lines.length < 2) return null;
  const delimiter = detectDelimiter(lines);
  const commaDecimal = delimiter === ";";

  let skipped = 0;
  const ibkr = ibkrPositions(lines, delimiter);
  if (ibkr) {
    lines = ibkr.lines;
    skipped = ibkr.skipped;
  }

  // Los brókers suelen poner un título o datos de la cuenta antes de la
  // tabla: el encabezado es la primera fila (de las primeras 30) que mapea.
  let headerIdx = -1;
  let columns: Partial<Record<Field, number>> | null = null;
  for (let i = 0; i < Math.min(lines.length, 30); i++) {
    columns = mapColumns(splitLine(lines[i], delimiter));
    if (columns) {
      headerIdx = i;
      break;
    }
  }
  if (!columns || headerIdx < 0) return null;
  const cols = columns;

  const records = lines.slice(headerIdx + 1).map((l) => splitLine(l, delimiter));
  const cell = (r: string[], f: Field) => (cols[f] === undefined ? undefined : r[cols[f]!]);
  const { order, ambiguous } = dateOrder(records.map((r) => cell(r, "date") ?? ""));

  const rows: ImportRow[] = [];
  let cash = 0;
  for (const r of records) {
    const rawTicker = cell(r, "ticker") ?? "";
    if (!rawTicker.trim()) continue;
    const ticker = normalizeTicker(rawTicker);
    const quantity = parseNumber(cell(r, "quantity"), commaDecimal);
    if (!ticker) {
      if (/^(cash|efectivo|usd|eur|ars|uyu)/i.test(rawTicker.trim())) cash++;
      else if (!/^(sub)?total/i.test(rawTicker.trim())) skipped++;
      continue;
    }
    if (quantity === null || !(quantity > 0)) {
      skipped++;
      continue;
    }
    let price = parseNumber(cell(r, "price"), commaDecimal);
    if (price === null || !(price > 0)) {
      const total = parseNumber(cell(r, "total_cost"), commaDecimal);
      price = total !== null && total > 0 ? total / quantity : null;
    }
    rows.push({
      ticker,
      name: cell(r, "name")?.trim() || null,
      quantity,
      purchase_price: price,
      purchase_date: parseDate(cell(r, "date"), order),
      currency: cell(r, "currency")?.trim().toUpperCase() || null,
    });
  }
  if (rows.length === 0) return null;

  const warnings: ImportWarning[] = [];
  if (skipped > 0) warnings.push({ type: "skipped_rows", count: skipped });
  if (cash > 0) warnings.push({ type: "cash_skipped", count: cash });
  if (ambiguous) warnings.push({ type: "ambiguous_dates" });
  return { rows, warnings, format: ibkr ? "ibkr" : "generic" };
}

// Filas de una importación: lo que devuelve `statement-import` a la app,
// salga del lector de CSV o de la IA. Puro.

export type ImportRow = {
  /// Ticker en el formato de Porty (el de Yahoo: `AAPL`, `BRK-B`, `GGAL.BA`).
  ticker: string;
  /// Nombre del instrumento si el archivo lo trae (solo para mostrar).
  name: string | null;
  quantity: number;
  /// Precio de compra promedio por unidad. `null` = el archivo no lo dice
  /// (la app lo pide antes de importar).
  purchase_price: number | null;
  /// "YYYY-MM-DD". `null` = el archivo no lo dice.
  purchase_date: string | null;
  /// Moneda que informa el archivo ("USD", "EUR"…), si la informa.
  currency: string | null;
};

/// Avisos para la vista previa (la app los traduce por `type`).
export type ImportWarning =
  | { type: "skipped_rows"; count: number }
  | { type: "ambiguous_dates" }
  | { type: "truncated"; limit: number }
  | { type: "cash_skipped"; count: number }
  | { type: "non_usd_currency"; currencies: string[] };

/// Más filas que esto no entran en una vista previa razonable.
export const maxRows = 200;

/// Lo que no es una inversión: efectivo y totales.
const notAHolding = /^(CASH|USD|EUR|ARS|UYU|BRL|MXN|GBP|TOTAL|TOTALES|SUBTOTAL|EFECTIVO|SALDO)$/;

/// Normaliza un ticker: mayúsculas, sin prefijo de bolsa (`NASDAQ:AAPL`),
/// sin el `.US` de algunos brókers y con guion para las clases de acciones
/// (`BRK.B` → `BRK-B`, como Yahoo). Los sufijos de bolsa de Yahoo (`.L`,
/// `.BA`, `.TO`…) se respetan. `null` si no parece un ticker.
export function normalizeTicker(raw: string): string | null {
  let t = raw.trim().toUpperCase().replace(/\s+/g, "");
  if (t.includes(":")) t = t.slice(t.lastIndexOf(":") + 1);
  t = t.replace(/\.US$/, "");
  // Clase de acción de una letra: BRK.B, BF.B → con guion. Un sufijo de
  // bolsa de Yahoo es de 1 o 2 letras también, pero solo en estas listas.
  const m = t.match(/^([A-Z]{1,5})\.([A-Z])$/);
  if (m && !yahooOneLetterSuffixes.has(m[2])) t = `${m[1]}-${m[2]}`;
  if (!/^[A-Z0-9^][A-Z0-9.\-=^]{0,14}$/.test(t)) return null;
  if (notAHolding.test(t)) return null;
  return t;
}

/// Sufijos de bolsa de Yahoo de una sola letra: Londres, Tokio, TSX
/// Venture y Frankfurt (`BP.L` no es la clase L de BP).
const yahooOneLetterSuffixes = new Set(["L", "T", "V", "F"]);

export function isoDate(year: number, month: number, day: number): string | null {
  if (!(year >= 1970 && year <= 2100 && month >= 1 && month <= 12 && day >= 1 && day <= 31)) return null;
  const d = new Date(Date.UTC(year, month - 1, day));
  if (d.getUTCMonth() !== month - 1) return null;
  return d.toISOString().slice(0, 10);
}

/// Deja las filas listas para la app: tickers normalizados, cantidades y
/// precios positivos, sin fechas futuras, como mucho [maxRows].
export function finalizeRows(
  rows: ImportRow[],
  today: string,
): { rows: ImportRow[]; warnings: ImportWarning[] } {
  const out: ImportRow[] = [];
  let skipped = 0;
  for (const r of rows) {
    const ticker = normalizeTicker(r.ticker ?? "");
    if (!ticker || !(Number.isFinite(r.quantity) && r.quantity > 0)) {
      skipped++;
      continue;
    }
    const price = r.purchase_price !== null && Number.isFinite(r.purchase_price) && r.purchase_price > 0
      ? round(r.purchase_price, 6)
      : null;
    const date = r.purchase_date && /^\d{4}-\d{2}-\d{2}$/.test(r.purchase_date) && r.purchase_date <= today
      ? r.purchase_date
      : null;
    const currency = r.currency && /^[A-Z]{3}$/.test(r.currency.trim().toUpperCase())
      ? r.currency.trim().toUpperCase()
      : null;
    const name = r.name?.trim() ? r.name.trim().slice(0, 80) : null;
    out.push({ ticker, name, quantity: round(r.quantity, 8), purchase_price: price, purchase_date: date, currency });
  }
  const warnings: ImportWarning[] = [];
  if (skipped > 0) warnings.push({ type: "skipped_rows", count: skipped });
  if (out.length > maxRows) warnings.push({ type: "truncated", limit: maxRows });
  const currencies = [...new Set(out.map((r) => r.currency).filter((c): c is string => !!c && c !== "USD"))].sort();
  if (currencies.length > 0) warnings.push({ type: "non_usd_currency", currencies });
  return { rows: out.slice(0, maxRows), warnings };
}

function round(v: number, decimals: number): number {
  const f = 10 ** decimals;
  return Math.round(v * f) / f;
}

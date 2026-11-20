// De las operaciones de una cuenta (SnapTrade `/activities`) a las compras
// que siguen abiertas y las ventas cerradas, por ticker. Las ventas
// consumen las compras más viejas primero (FIFO), como hace Porty con las
// ventas manuales.

export type Trade = {
  id: string;
  /// BUY, SELL o REI (reinversión de dividendos: una compra).
  type: string;
  ticker: string;
  units: number;
  price: number;
  fee: number;
  /// ISO 8601.
  date: string;
};

export type Lot = {
  /// El id de la compra en SnapTrade; `rest` para lo que el historial no
  /// explica.
  id: string;
  units: number;
  price: number;
  date: string;
  /// La fecha y el precio no salen de una compra: lo que el historial no
  /// explica (transferencias, compras de antes del historial).
  estimated: boolean;
};

export type Closed = {
  /// El id de la venta en SnapTrade.
  id: string;
  units: number;
  avgPurchasePrice: number;
  closePrice: number;
  closeDate: string;
  realizedPnl: number;
};

const epsilon = 1e-6;

/// Las compras abiertas y las ventas de UN ticker de una cuenta.
/// [heldUnits] es lo que el bróker dice que tiene hoy y manda sobre el
/// historial: si el historial explica más, se recortan las compras más
/// viejas; si explica menos, la diferencia va como una compra estimada al
/// costo que informa el bróker ([costBasis], por acción).
export function lotsFor(
  trades: Trade[],
  heldUnits: number,
  costBasis: number | null,
  currentPrice: number,
  now: string,
): { lots: Lot[]; closed: Closed[] } {
  const sorted = [...trades].sort((a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id));
  const open: Lot[] = [];
  const closed: Closed[] = [];
  for (const t of sorted) {
    if (!(t.units > 0) || !(t.price > 0)) continue;
    if (t.type === "BUY" || t.type === "REI") {
      // La comisión de la compra va al costo, como en el resto de Porty.
      open.push({ id: t.id, units: t.units, price: t.price + t.fee / t.units, date: t.date, estimated: false });
      continue;
    }
    if (t.type !== "SELL") continue;
    let left = t.units;
    let cost = 0;
    let matched = 0;
    while (left > epsilon && open.length > 0) {
      const lot = open[0];
      const take = Math.min(lot.units, left);
      cost += take * lot.price;
      matched += take;
      lot.units -= take;
      left -= take;
      if (lot.units <= epsilon) open.shift();
    }
    // Una venta de algo que el historial no muestra comprado: no se inventa
    // el costo.
    if (matched <= epsilon) continue;
    const avg = cost / matched;
    closed.push({
      id: t.id,
      units: matched,
      avgPurchasePrice: avg,
      closePrice: t.price,
      closeDate: t.date,
      realizedPnl: (t.price - avg) * matched - t.fee,
    });
  }

  let explained = open.reduce((s, l) => s + l.units, 0);
  // El historial explica de más (vendió o transfirió algo que no figura):
  // se recortan las compras más viejas.
  while (explained - heldUnits > epsilon && open.length > 0) {
    const extra = explained - heldUnits;
    const lot = open[0];
    if (lot.units <= extra + epsilon) {
      explained -= lot.units;
      open.shift();
    } else {
      lot.units -= extra;
      explained -= extra;
    }
  }
  const missing = heldUnits - explained;
  if (missing > epsilon) {
    // Con el costo total del bróker, lo que falta cuesta lo que no explican
    // las compras; si da raro (o no hay costo), el costo del bróker o el
    // precio de hoy.
    const openCost = open.reduce((s, l) => s + l.units * l.price, 0);
    const fromBroker = costBasis !== null && costBasis > 0 ? (costBasis * heldUnits - openCost) / missing : null;
    const price = fromBroker !== null && fromBroker > 0 ? fromBroker : costBasis ?? currentPrice;
    open.unshift({ id: "rest", units: missing, price, date: now, estimated: true });
  }
  return { lots: open, closed };
}

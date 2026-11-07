// Mapeo de posiciones de eToro al modelo de Porty. Funciones puras: sin red,
// sin base, sin reloj.
//
// Regla general (docs/superpowers/research/2026-10-08-etoro-integration.md
// §4): solo entra como posición de Porty lo que se puede representar sin
// deformarlo — acciones y ETFs de bolsas de EE.UU., compradas, sin
// apalancamiento, como activo real y fuera de copy trading. Todo lo demás se
// informa en "no importado" con un motivo, nunca se fuerza.

/// Una posición abierta tal como la devuelve `GET /trading/info/real/pnl`
/// (`clientPortfolio.positions[]`). La spec usa sufijo en mayúscula
/// (`positionID`); algunos ejemplos traen camelCase: se aceptan ambos.
export type EtoroOpenPosition = Record<string, unknown>;

/// Una operación cerrada de `GET /trading/info/trade/history`.
export type EtoroClosedTrade = Record<string, unknown>;

/// Metadata de un instrumento (de `/market-data/instruments` + catálogos).
export type InstrumentMeta = {
  instrumentId: number;
  symbolFull: string;
  displayName?: string | null;
  instrumentType?: string | null;
  exchange?: string | null;
  /// Logo que publica eToro (`images[]` de `/market-data/instruments`).
  logoUrl?: string | null;
};

export type NotImportedReason =
  | "cfd"
  | "leveraged"
  | "short"
  | "copy_trading"
  | "crypto"
  | "non_us"
  | "unsupported_type"
  | "unknown_instrument";

export type PortyOpenRow = {
  externalId: string;
  ticker: string;
  quantity: number;
  purchasePrice: number;
  purchaseDate: string;
  /// Precio actual según eToro (`unrealizedPnL.closeRate`). La app lo usa
  /// solo si no tiene cotización propia.
  brokerPrice: number | null;
};

export type PortyClosedRow = {
  externalId: string;
  ticker: string;
  quantity: number;
  avgPurchasePrice: number;
  closePrice: number;
  closeDate: string;
  realizedPnl: number | null;
};

/// Lo que el usuario tiene en eToro y Porty no importa como posición
/// (cripto, CFD, fuera de EE.UU., apalancadas, cortos), con el valor y el
/// P&L que calcula eToro, para mostrarlo aparte. Copy trading no entra
/// (decisión 6 de la investigación: por ahora no se muestra).
export type OtherHolding = {
  ticker: string;
  name: string | null;
  reason: NotImportedReason;
  /// Cuántas posiciones de eToro se agruparon.
  count: number;
  units: number;
  /// Lo invertido (`amount`), en USD.
  investedUsd: number;
  /// Valor actual en USD: invertido + P&L no realizado.
  valueUsd: number;
  pnlUsd: number;
};

export type NotImportedItem = {
  ticker: string;
  name: string | null;
  reason: NotImportedReason;
  count: number;
};

/// Tipos de liquidación (`settlementTypeID`) según la spec de eToro.
export const settlementType = {
  cfd: 0,
  realAsset: 1,
  swap: 2,
  cryptoMarginTrade: 3,
  futureContract: 4,
} as const;

/// Bolsas de EE.UU. que Porty cotiza (por nombre: eToro no publica ids
/// estables en la doc). La prueba en vivo devolvió "Nasdaq" y "NYSE".
const usExchangePattern = /^(nasdaq|nyse|nyse arca|nyse american|amex|bats|cboe)\b/i;

function pick<T = unknown>(row: Record<string, unknown>, ...keys: string[]): T | undefined {
  for (const k of keys) {
    if (row[k] !== undefined && row[k] !== null) return row[k] as T;
  }
  return undefined;
}

function num(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "" && Number.isFinite(Number(value))) {
    return Number(value);
  }
  return null;
}

/// Ticker de Porty a partir del `symbolFull` de eToro. eToro agrega `.US` a
/// algunas acciones de Nasdaq/NYSE (prueba en vivo: `DASH.US`); las clases de
/// acciones (`BRK.B`) quedan como están, Porty ya las convierte para Yahoo.
export function portyTicker(symbolFull: string): string {
  return symbolFull.trim().toUpperCase().replace(/\.US$/, "");
}

export type AssetKind = "stock_or_etf" | "crypto" | "other";

export function assetKind(meta: InstrumentMeta): AssetKind {
  const t = (meta.instrumentType ?? "").toLowerCase();
  if (/crypto/.test(t)) return "crypto";
  if (/stock|etf/.test(t)) return "stock_or_etf";
  return "other";
}

export function isUsListing(meta: InstrumentMeta): boolean {
  return usExchangePattern.test((meta.exchange ?? "").trim());
}

export type OpenDecision =
  | { kind: "import"; row: PortyOpenRow }
  | { kind: "skip"; reason: NotImportedReason };

/// Decide qué hacer con una posición abierta. El orden importa: primero lo
/// que la vuelve no representable aunque el activo sea "bueno" (copy,
/// corto, apalancada, CFD), después el tipo de activo y la bolsa.
export function classifyOpen(
  position: EtoroOpenPosition,
  meta: InstrumentMeta | undefined,
): OpenDecision {
  const mirrorId = num(pick(position, "mirrorID", "mirrorId")) ?? 0;
  if (mirrorId > 0) return { kind: "skip", reason: "copy_trading" };

  if (pick<boolean>(position, "isBuy") === false) return { kind: "skip", reason: "short" };

  const leverage = num(pick(position, "leverage")) ?? 1;
  if (leverage > 1) return { kind: "skip", reason: "leveraged" };

  if (!meta) return { kind: "skip", reason: "unknown_instrument" };
  const kind = assetKind(meta);
  if (kind === "crypto") return { kind: "skip", reason: "crypto" };
  // Materias primas, divisas e índices: el motivo que entiende el usuario es
  // el tipo de activo (en eToro además son siempre CFD).
  if (kind !== "stock_or_etf") return { kind: "skip", reason: "unsupported_type" };

  const settlement = num(pick(position, "settlementTypeID", "settlementTypeId"));
  if (settlement !== settlementType.realAsset) return { kind: "skip", reason: "cfd" };

  if (!isUsListing(meta)) return { kind: "skip", reason: "non_us" };

  const positionId = pick(position, "positionID", "positionId");
  const units = num(pick(position, "units"));
  const openRate = num(pick(position, "openRate"));
  const openDate = pick<string>(position, "openDateTime", "openDate");
  if (positionId === undefined || !units || units <= 0 || !openRate || openRate <= 0 || !openDate) {
    return { kind: "skip", reason: "unknown_instrument" };
  }

  return {
    kind: "import",
    row: {
      externalId: String(positionId),
      ticker: portyTicker(meta.symbolFull),
      quantity: units,
      // Para acciones de EE.UU. `openRate` es el precio en USD (verificado:
      // coincide con amount/units en la prueba en vivo).
      purchasePrice: openRate,
      purchaseDate: new Date(openDate).toISOString(),
      brokerPrice: currentRate(position),
    },
  };
}

function unrealized(position: EtoroOpenPosition): Record<string, unknown> | null {
  const u = pick(position, "unrealizedPnL", "unrealizedPnl");
  return u && typeof u === "object" ? u as Record<string, unknown> : null;
}

/// Precio actual de eToro para la posición, o null si no vino.
export function currentRate(position: EtoroOpenPosition): number | null {
  const u = unrealized(position);
  const rate = u ? num(pick(u, "closeRate")) : null;
  return rate !== null && rate > 0 ? rate : null;
}

/// P&L no realizado en USD. eToro lo da en la moneda del activo y en la de la
/// cuenta; con la conversión a USD del momento (`closeConversionRate`, la
/// misma que usa para `openConversionRate`) no depende de la moneda de la
/// cuenta. Si falta la conversión, se usa el de la cuenta.
export function unrealizedPnlUsd(position: EtoroOpenPosition): number | null {
  const u = unrealized(position);
  if (!u) return null;
  const asset = num(pick(u, "pnlAssetCurrency"));
  const conversion = num(pick(u, "closeConversionRate"));
  if (asset !== null && conversion !== null && conversion > 0) return asset * conversion;
  return num(pick(u, "pnL", "pnl"));
}

export type ClosedDecision =
  | { kind: "import"; row: PortyClosedRow }
  | { kind: "skip"; reason: NotImportedReason };

/// Igual que [classifyOpen] para el historial. El historial NO trae el tipo
/// de liquidación ni el mirror: se filtra por apalancamiento, dirección,
/// `parentPositionId` (copiadas) y tipo/bolsa del instrumento.
export function classifyClosed(
  trade: EtoroClosedTrade,
  meta: InstrumentMeta | undefined,
): ClosedDecision {
  const parent = num(pick(trade, "parentPositionId", "parentPositionID")) ?? 0;
  if (parent > 0) return { kind: "skip", reason: "copy_trading" };
  if (pick<boolean>(trade, "isBuy") === false) return { kind: "skip", reason: "short" };
  const leverage = num(pick(trade, "leverage")) ?? 1;
  if (leverage > 1) return { kind: "skip", reason: "leveraged" };
  if (!meta) return { kind: "skip", reason: "unknown_instrument" };
  const kind = assetKind(meta);
  if (kind === "crypto") return { kind: "skip", reason: "crypto" };
  if (kind !== "stock_or_etf") return { kind: "skip", reason: "unsupported_type" };
  if (!isUsListing(meta)) return { kind: "skip", reason: "non_us" };

  const positionId = pick(trade, "positionId", "positionID");
  const units = num(pick(trade, "units"));
  const openRate = num(pick(trade, "openRate"));
  const closeRate = num(pick(trade, "closeRate"));
  const closeDate = pick<string>(trade, "closeTimestamp", "closeDateTime");
  if (positionId === undefined || !units || units <= 0 || !openRate || !closeRate || !closeDate) {
    return { kind: "skip", reason: "unknown_instrument" };
  }
  return {
    kind: "import",
    row: {
      // Un cierre parcial genera otra fila con el mismo positionId (prueba en
      // vivo): la clave incluye fecha y unidades cerradas.
      externalId: `${positionId}:${new Date(closeDate).toISOString()}:${units}`,
      ticker: portyTicker(meta.symbolFull),
      quantity: units,
      avgPurchasePrice: openRate,
      closePrice: closeRate,
      closeDate: new Date(closeDate).toISOString(),
      realizedPnl: num(pick(trade, "netProfit")),
    },
  };
}

export type MappedPortfolio = {
  open: PortyOpenRow[];
  closed: PortyClosedRow[];
  notImported: NotImportedItem[];
  closedNotImported: NotImportedItem[];
  otherHoldings: OtherHolding[];
  /// Logo de eToro por ticker, para todo lo abierto (importado o no).
  logos: Record<string, string>;
};

function addOther(
  acc: Map<string, OtherHolding>,
  meta: InstrumentMeta | undefined,
  instrumentId: unknown,
  reason: NotImportedReason,
  position: EtoroOpenPosition,
) {
  if (reason === "copy_trading") return;
  const invested = num(pick(position, "amount"));
  const pnl = unrealizedPnlUsd(position);
  // Sin lo invertido o sin P&L no hay valor que mostrar sin inventarlo.
  if (invested === null || pnl === null) return;
  const ticker = meta ? portyTicker(meta.symbolFull) : `#${instrumentId ?? "?"}`;
  const key = `${ticker}|${reason}`;
  const units = num(pick(position, "units")) ?? 0;
  const prev = acc.get(key);
  if (prev) {
    prev.count += 1;
    prev.units += units;
    prev.investedUsd += invested;
    prev.pnlUsd += pnl;
    prev.valueUsd = prev.investedUsd + prev.pnlUsd;
  } else {
    acc.set(key, {
      ticker,
      name: meta?.displayName ?? null,
      reason,
      count: 1,
      units,
      investedUsd: invested,
      pnlUsd: pnl,
      valueUsd: invested + pnl,
    });
  }
}

function addSkip(
  acc: Map<string, NotImportedItem>,
  meta: InstrumentMeta | undefined,
  instrumentId: unknown,
  reason: NotImportedReason,
) {
  const ticker = meta ? portyTicker(meta.symbolFull) : `#${instrumentId ?? "?"}`;
  const key = `${ticker}|${reason}`;
  const prev = acc.get(key);
  if (prev) prev.count += 1;
  else acc.set(key, { ticker, name: meta?.displayName ?? null, reason, count: 1 });
}

/// Mapea la foto completa: abiertas + historial. Las posiciones de copy
/// aparecen dos veces en eToro (`positions[]` con mirrorID>0 y
/// `mirrors[].positions[]`): acá solo se usa `positions[]`.
export function mapPortfolio(
  positions: EtoroOpenPosition[],
  history: EtoroClosedTrade[],
  instruments: Map<number, InstrumentMeta>,
): MappedPortfolio {
  const open: PortyOpenRow[] = [];
  const skipped = new Map<string, NotImportedItem>();
  const others = new Map<string, OtherHolding>();
  const logos: Record<string, string> = {};
  for (const p of positions) {
    const id = num(pick(p, "instrumentID", "instrumentId"));
    const meta = id === null ? undefined : instruments.get(id);
    const decision = classifyOpen(p, meta);
    if (decision.kind === "import") {
      open.push(decision.row);
    } else {
      addSkip(skipped, meta, id, decision.reason);
      addOther(others, meta, id, decision.reason, p);
    }
    if (meta?.logoUrl) logos[portyTicker(meta.symbolFull)] = meta.logoUrl;
  }

  const closed: PortyClosedRow[] = [];
  const closedSkipped = new Map<string, NotImportedItem>();
  const seen = new Set<string>();
  for (const t of history) {
    const id = num(pick(t, "instrumentId", "instrumentID"));
    const meta = id === null ? undefined : instruments.get(id);
    const decision = classifyClosed(t, meta);
    if (decision.kind === "import") {
      // Las ventanas del historial se pisan: una misma operación no entra dos
      // veces.
      if (seen.has(decision.row.externalId)) continue;
      seen.add(decision.row.externalId);
      closed.push(decision.row);
    } else {
      addSkip(closedSkipped, meta, id, decision.reason);
    }
  }

  return {
    open,
    closed,
    notImported: [...skipped.values()],
    closedNotImported: [...closedSkipped.values()],
    otherHoldings: [...others.values()]
      .map((o) => ({
        ...o,
        investedUsd: round2(o.investedUsd),
        pnlUsd: round2(o.pnlUsd),
        valueUsd: round2(o.valueUsd),
      }))
      .sort((a, b) => b.valueUsd - a.valueUsd),
    logos,
  };
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/// El logo de eToro más adecuado para un avatar chico: el cuadrado más
/// cercano a 150 px (eToro publica varios tamaños). Solo URLs HTTPS.
export function pickLogo(images: unknown): string | null {
  if (!Array.isArray(images)) return null;
  let best: { uri: string; score: number } | null = null;
  for (const raw of images) {
    if (!raw || typeof raw !== "object") continue;
    const img = raw as Record<string, unknown>;
    const uri = typeof img.uri === "string" ? img.uri.trim() : "";
    if (!uri.startsWith("https://")) continue;
    const w = num(img.width) ?? 0;
    const h = num(img.height) ?? w;
    const score = Math.abs(w - 150) + Math.abs(w - h) * 2;
    if (!best || score < best.score) best = { uri, score };
  }
  return best?.uri ?? null;
}

/// Tickers que el usuario ya tenía cargados a mano y también vienen de
/// eToro. No se fusiona ni se borra nada: la app le pregunta al usuario.
export function possibleDuplicates(manualTickers: string[], imported: PortyOpenRow[]): string[] {
  const manual = new Set(manualTickers.map((t) => t.trim().toUpperCase()));
  return [...new Set(imported.map((r) => r.ticker))].filter((t) => manual.has(t)).sort();
}

/// Todos los instrumentos que hay que resolver (abiertas + historial).
export function instrumentIds(positions: EtoroOpenPosition[], history: EtoroClosedTrade[]): number[] {
  const ids = new Set<number>();
  for (const p of positions) {
    const id = num(pick(p, "instrumentID", "instrumentId"));
    if (id !== null) ids.add(id);
  }
  for (const t of history) {
    const id = num(pick(t, "instrumentId", "instrumentID"));
    if (id !== null) ids.add(id);
  }
  return [...ids].sort((a, b) => a - b);
}

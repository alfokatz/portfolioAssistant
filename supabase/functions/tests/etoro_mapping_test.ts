// Mapeo eToro → Porty: un caso por cada tipo de posición de la investigación
// (docs/superpowers/research/2026-10-08-etoro-integration.md §4). Sin red ni
// base: corre con `deno test tests/etoro_mapping_test.ts`.

import { assertEquals } from "jsr:@std/assert@1";
import {
  classifyClosed,
  classifyOpen,
  type InstrumentMeta,
  instrumentIds,
  currentRate,
  mapPortfolio,
  pickLogo,
  portyTicker,
  possibleDuplicates,
} from "../etoro-sync/mapping.ts";

const meta: Record<string, InstrumentMeta> = {
  aapl: { instrumentId: 1001, symbolFull: "AAPL", displayName: "Apple", instrumentType: "Stocks", exchange: "Nasdaq" },
  voo: { instrumentId: 1002, symbolFull: "VOO", displayName: "Vanguard S&P 500", instrumentType: "ETF", exchange: "NYSE" },
  dash: { instrumentId: 1003, symbolFull: "DASH.US", displayName: "DoorDash", instrumentType: "Stocks", exchange: "Nasdaq" },
  brk: { instrumentId: 1004, symbolFull: "BRK.B", displayName: "Berkshire B", instrumentType: "Stocks", exchange: "NYSE" },
  bp: { instrumentId: 2001, symbolFull: "BP.L", displayName: "BP", instrumentType: "Stocks", exchange: "LSE" },
  btc: { instrumentId: 100000, symbolFull: "BTC", displayName: "Bitcoin", instrumentType: "Crypto", exchange: "Digital Currency" },
  gold: { instrumentId: 18, symbolFull: "GOLD", displayName: "Gold", instrumentType: "Commodity", exchange: "FX" },
  eurusd: { instrumentId: 1, symbolFull: "EURUSD", displayName: "EUR/USD", instrumentType: "Forex", exchange: "FX" },
  spx: { instrumentId: 27, symbolFull: "SPX500", displayName: "US500", instrumentType: "Indices", exchange: "FX" },
};

function position(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    positionID: 1,
    instrumentID: 1001,
    mirrorID: 0,
    settlementTypeID: 1,
    isBuy: true,
    leverage: 1,
    units: 10,
    openRate: 180,
    amount: 1800,
    openDateTime: "2025-03-10T14:31:00Z",
    ...over,
  };
}

Deno.test("acción de EE.UU. sin apalancamiento como activo real → se importa tal cual", () => {
  const d = classifyOpen(position(), meta.aapl);
  assertEquals(d, {
    kind: "import",
    row: {
      externalId: "1",
      ticker: "AAPL",
      quantity: 10,
      purchasePrice: 180,
      purchaseDate: "2025-03-10T14:31:00.000Z",
      brokerPrice: null,
    },
  });
});

Deno.test("ETF con fracciones → se importa con la cantidad exacta", () => {
  const d = classifyOpen(position({ instrumentID: 1002, units: 0.137254, openRate: 510.25 }), meta.voo);
  assertEquals(d.kind, "import");
  if (d.kind === "import") assertEquals(d.row.quantity, 0.137254);
});

Deno.test("acepta también los nombres camelCase de algunos ejemplos de eToro", () => {
  const d = classifyOpen(
    { positionId: 9, instrumentId: 1001, mirrorId: 0, settlementTypeId: 1, isBuy: true, leverage: 1, units: 1, openRate: 2, openDateTime: "2026-01-01T00:00:00Z" },
    meta.aapl,
  );
  assertEquals(d.kind, "import");
});

Deno.test("CFD comprado sin apalancamiento → aparte (no es propiedad del activo)", () => {
  assertEquals(classifyOpen(position({ settlementTypeID: 0 }), meta.aapl), { kind: "skip", reason: "cfd" });
});

Deno.test("apalancada → no se importa", () => {
  assertEquals(classifyOpen(position({ leverage: 5 }), meta.aapl), { kind: "skip", reason: "leveraged" });
});

Deno.test("en corto → no se importa", () => {
  assertEquals(classifyOpen(position({ isBuy: false, settlementTypeID: 0 }), meta.aapl), { kind: "skip", reason: "short" });
});

Deno.test("copy trading / Smart Portfolio (mirrorID > 0) → no se importa", () => {
  assertEquals(classifyOpen(position({ mirrorID: 77 }), meta.aapl), { kind: "skip", reason: "copy_trading" });
});

Deno.test("cripto (real o CFD) → aparte en la v1", () => {
  assertEquals(classifyOpen(position({ instrumentID: 100000 }), meta.btc), { kind: "skip", reason: "crypto" });
  assertEquals(classifyOpen(position({ instrumentID: 100000, settlementTypeID: 3 }), meta.btc), {
    kind: "skip",
    reason: "crypto",
  });
});

Deno.test("materias primas, divisas e índices → tipo no soportado", () => {
  for (const m of [meta.gold, meta.eurusd, meta.spx]) {
    assertEquals(classifyOpen(position({ instrumentID: m.instrumentId, settlementTypeID: 0 }), m), {
      kind: "skip",
      reason: "unsupported_type",
    });
  }
});

Deno.test("acción fuera de EE.UU. → aparte (Porty no la cotiza)", () => {
  assertEquals(classifyOpen(position({ instrumentID: 2001 }), meta.bp), { kind: "skip", reason: "non_us" });
});

Deno.test("la bolsa decide, no el sufijo: DASH.US (Nasdaq) entra como DASH y BRK.B (NYSE) como BRK.B", () => {
  const dash = classifyOpen(position({ instrumentID: 1003 }), meta.dash);
  const brk = classifyOpen(position({ instrumentID: 1004 }), meta.brk);
  assertEquals(dash.kind === "import" && dash.row.ticker, "DASH");
  assertEquals(brk.kind === "import" && brk.row.ticker, "BRK.B");
  assertEquals(portyTicker(" dash.us "), "DASH");
});

Deno.test("instrumento sin metadata → no se importa (nunca se adivina el ticker)", () => {
  assertEquals(classifyOpen(position({ instrumentID: 555 }), undefined), { kind: "skip", reason: "unknown_instrument" });
});

Deno.test("datos incompletos (sin unidades o precio) → no se importa", () => {
  assertEquals(classifyOpen(position({ units: 0 }), meta.aapl).kind, "skip");
  assertEquals(classifyOpen(position({ openRate: null }), meta.aapl).kind, "skip");
});

Deno.test("varias compras del mismo activo → un lote de Porty por posición de eToro", () => {
  const instruments = new Map([[1001, meta.aapl]]);
  const mapped = mapPortfolio(
    [
      position({ positionID: 1, units: 10, openRate: 180, openDateTime: "2025-03-10T14:31:00Z" }),
      position({ positionID: 2, units: 5, openRate: 210, openDateTime: "2026-01-05T15:00:00Z" }),
    ],
    [],
    instruments,
  );
  assertEquals(mapped.open.map((r) => [r.externalId, r.quantity, r.purchasePrice]), [
    ["1", 10, 180],
    ["2", 5, 210],
  ]);
});

Deno.test("lo no importado se agrupa por ticker y motivo, con cantidad", () => {
  const instruments = new Map(Object.values(meta).map((m) => [m.instrumentId, m]));
  const mapped = mapPortfolio(
    [
      position({ positionID: 1 }),
      position({ positionID: 2, leverage: 2 }),
      position({ positionID: 3, leverage: 2 }),
      position({ positionID: 4, instrumentID: 100000 }),
      position({ positionID: 5, instrumentID: 777 }),
    ],
    [],
    instruments,
  );
  assertEquals(mapped.open.length, 1);
  assertEquals(mapped.notImported, [
    { ticker: "AAPL", name: "Apple", reason: "leveraged", count: 2 },
    { ticker: "BTC", name: "Bitcoin", reason: "crypto", count: 1 },
    { ticker: "#777", name: null, reason: "unknown_instrument", count: 1 },
  ]);
});

function trade(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    positionId: 900,
    instrumentId: 1004,
    isBuy: true,
    leverage: 1,
    openRate: 300,
    closeRate: 320,
    units: 2,
    netProfit: 38.5,
    fees: 1.5,
    parentPositionId: 0,
    openTimestamp: "2025-01-01T15:00:00Z",
    closeTimestamp: "2026-06-24T15:00:00Z",
    ...over,
  };
}

Deno.test("cerrada: precio de compra, de venta y la ganancia neta de eToro", () => {
  const d = classifyClosed(trade(), meta.brk);
  assertEquals(d.kind, "import");
  if (d.kind === "import") {
    assertEquals(d.row.ticker, "BRK.B");
    assertEquals(d.row.avgPurchasePrice, 300);
    assertEquals(d.row.closePrice, 320);
    assertEquals(d.row.realizedPnl, 38.5);
    assertEquals(d.row.closeDate, "2026-06-24T15:00:00.000Z");
  }
});

Deno.test("cerrada sin netProfit → realizedPnl null (Porty la calcula)", () => {
  const d = classifyClosed(trade({ netProfit: undefined }), meta.brk);
  assertEquals(d.kind === "import" && d.row.realizedPnl, null);
});

Deno.test("cerradas: copiada, corta o apalancada no entran", () => {
  assertEquals(classifyClosed(trade({ parentPositionId: 123 }), meta.brk), { kind: "skip", reason: "copy_trading" });
  assertEquals(classifyClosed(trade({ isBuy: false }), meta.brk), { kind: "skip", reason: "short" });
  assertEquals(classifyClosed(trade({ leverage: 2 }), meta.brk), { kind: "skip", reason: "leveraged" });
});

Deno.test("cierres parciales de la misma posición → filas distintas; repetidas entre ventanas → una sola", () => {
  const instruments = new Map([[1004, meta.brk]]);
  const a = trade({ units: 1, closeTimestamp: "2026-06-24T15:00:00Z" });
  const b = trade({ units: 1.5, closeTimestamp: "2026-06-24T15:30:00Z" });
  const mapped = mapPortfolio([], [a, b, { ...a }], instruments);
  assertEquals(mapped.closed.length, 2);
  assertEquals(new Set(mapped.closed.map((r) => r.externalId)).size, 2);
});

Deno.test("posibles duplicados: tickers cargados a mano que también vienen de eToro", () => {
  const instruments = new Map([[1001, meta.aapl], [1002, meta.voo]]);
  const mapped = mapPortfolio(
    [position({ positionID: 1 }), position({ positionID: 2, instrumentID: 1002 })],
    [],
    instruments,
  );
  assertEquals(possibleDuplicates(["aapl", "MSFT"], mapped.open), ["AAPL"]);
  assertEquals(possibleDuplicates([], mapped.open), []);
});

Deno.test("instrumentIds junta abiertas e historial sin repetir", () => {
  assertEquals(instrumentIds([position(), position({ instrumentID: 1002 })], [trade(), trade()]), [1001, 1002, 1004]);
});

// ── Precio de eToro, otros activos y logos ──────────────────────────────────

function withPnl(over: Record<string, unknown>, u: Record<string, unknown>): Record<string, unknown> {
  return position({ ...over, unrealizedPnL: { closeConversionRate: 1, ...u } });
}

Deno.test("la posición importada lleva el precio actual de eToro", () => {
  const d = classifyOpen(withPnl({}, { closeRate: 231.5, pnlAssetCurrency: 515 }), meta.aapl);
  assertEquals(d.kind, "import");
  if (d.kind === "import") assertEquals(d.row.brokerPrice, 231.5);
});

Deno.test("sin unrealizedPnL o con precio inválido, no hay precio de eToro", () => {
  assertEquals(currentRate(position()), null);
  assertEquals(currentRate(withPnl({}, { closeRate: 0 })), null);
  assertEquals(currentRate(withPnl({}, { closeRate: "abc" })), null);
});

Deno.test("otros activos: valor = invertido + P&L de eToro, agrupado por ticker y motivo", () => {
  const instruments = new Map(Object.values(meta).map((m) => [m.instrumentId, m]));
  const mapped = mapPortfolio(
    [
      withPnl({ positionID: 1 }, { closeRate: 200, pnlAssetCurrency: 200 }), // importada
      withPnl({ positionID: 2, instrumentID: 100000, units: 0.01, amount: 950 }, { pnlAssetCurrency: 50 }),
      withPnl({ positionID: 3, instrumentID: 100000, units: 0.02, amount: 1000 }, { pnlAssetCurrency: -100 }),
      // Fuera de EE.UU.: P&L en libras convertido a USD.
      withPnl({ positionID: 4, instrumentID: 2001, units: 100, amount: 608 }, {
        pnlAssetCurrency: 10,
        closeConversionRate: 1.25,
      }),
      // Copy trading: no se muestra (decisión 6).
      withPnl({ positionID: 5, mirrorID: 7, amount: 500 }, { pnlAssetCurrency: 20 }),
      // Sin P&L: no se inventa un valor.
      position({ positionID: 6, instrumentID: 18, settlementTypeID: 0, amount: 300 }),
    ],
    [],
    instruments,
  );
  assertEquals(mapped.open.length, 1);
  assertEquals(mapped.otherHoldings, [
    { ticker: "BTC", name: "Bitcoin", reason: "crypto", count: 2, units: 0.03, investedUsd: 1950, pnlUsd: -50, valueUsd: 1900 },
    { ticker: "BP.L", name: "BP", reason: "non_us", count: 1, units: 100, investedUsd: 608, pnlUsd: 12.5, valueUsd: 620.5 },
  ]);
  // El motivo de "no importado" sigue incluyendo todo (también copy y sin P&L).
  assertEquals(mapped.notImported.map((n) => n.reason).sort(), ["copy_trading", "crypto", "non_us", "unsupported_type"]);
});

Deno.test("si falta la conversión se usa el P&L en la moneda de la cuenta", () => {
  const instruments = new Map([[meta.btc.instrumentId, meta.btc]]);
  const mapped = mapPortfolio(
    [position({ instrumentID: 100000, amount: 100, unrealizedPnL: { pnL: 7 } })],
    [],
    instruments,
  );
  assertEquals(mapped.otherHoldings[0].valueUsd, 107);
});

Deno.test("logos: por ticker, de todo lo abierto (importado o no)", () => {
  const withLogo = new Map<number, InstrumentMeta>([
    [1001, { ...meta.aapl, logoUrl: "https://etoro-cdn.etorostatic.com/market-avatars/aapl/150x150.png" }],
    [100000, { ...meta.btc, logoUrl: "https://etoro-cdn.etorostatic.com/market-avatars/btc/150x150.png" }],
    [1002, meta.voo],
  ]);
  const mapped = mapPortfolio(
    [position({ positionID: 1 }), position({ positionID: 2, instrumentID: 100000 }), position({ positionID: 3, instrumentID: 1002 })],
    [],
    withLogo,
  );
  assertEquals(mapped.logos, {
    AAPL: "https://etoro-cdn.etorostatic.com/market-avatars/aapl/150x150.png",
    BTC: "https://etoro-cdn.etorostatic.com/market-avatars/btc/150x150.png",
  });
});

Deno.test("pickLogo elige el cuadrado más cercano a 150 px y solo HTTPS", () => {
  assertEquals(
    pickLogo([
      { width: 35, height: 35, uri: "https://x/35.png" },
      { width: 150, height: 150, uri: "https://x/150.png" },
      { width: 90, height: 90, uri: "https://x/90.png" },
    ]),
    "https://x/150.png",
  );
  assertEquals(pickLogo([{ width: 150, height: 150, uri: "http://x/insecure.png" }]), null);
  assertEquals(pickLogo(undefined), null);
  assertEquals(pickLogo([{ uri: "https://x/sin-tamano.svg" }]), "https://x/sin-tamano.svg");
});

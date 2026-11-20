// Resultados del brief (solo Gold): `reported` = 8-K 2.02 desde el último
// cierre; `estimated` = próxima fecha estimada en los 3 días hábiles
// siguientes. Puro, sin red ni base.

import { assertEquals } from "jsr:@std/assert@1";
import { addBusinessDays, earningsOf, previousBusinessDay } from "../daily-brief/earnings.ts";
import type { Filing } from "../_shared/sec.ts";

const filing = (filed: string, items = ["2.02"], form = "8-K"): Filing => ({
  form, filed, report_date: null, items, accession: `0000-${filed}`, primary_document: "x.htm",
  url: `https://www.sec.gov/Archives/edgar/data/1/${filed}/x.htm`, index_url: "https://www.sec.gov/idx",
});

Deno.test("días hábiles: el último cierre salta el fin de semana", () => {
  // 2026-12-02 es miércoles; 2026-11-30, lunes.
  assertEquals(previousBusinessDay("2026-12-02"), "2026-12-01");
  assertEquals(previousBusinessDay("2026-11-30"), "2026-11-27"); // lunes → viernes
  assertEquals(previousBusinessDay("2026-11-29"), "2026-11-27"); // domingo → viernes
  assertEquals(addBusinessDays("2026-12-02", 3), "2026-12-07"); // mié + 3 hábiles = lun
  assertEquals(addBusinessDays("2026-12-04", 1), "2026-12-07");
});

Deno.test("earningsOf: reported si el 8-K 2.02 se presentó desde el último cierre, con link a la SEC", () => {
  const r = earningsOf("CRM", [filing("2026-12-01"), filing("2026-09-02")], "2026-12-02");
  assertEquals(r, { ticker: "CRM", kind: "reported", date: "2026-12-01", url: filing("2026-12-01").url });
  // Presentado hoy también cuenta.
  assertEquals(earningsOf("CRM", [filing("2026-12-02")], "2026-12-02")?.kind, "reported");
  // Otro ítem de 8-K (no 2.02) o más viejo que el último cierre: no es un resultado nuevo.
  assertEquals(earningsOf("CRM", [filing("2026-12-01", ["5.02"])], "2026-12-02"), null);
  assertEquals(earningsOf("CRM", [filing("2026-11-20")], "2026-12-02"), null);
});

Deno.test("earningsOf: estimated solo en los 3 días hábiles siguientes y sin link", () => {
  // Reportó el 2025-12-03 (mié): "mismo reporte un año después" = 364 días → 2026-12-02.
  // El brief del 2026-12-01 (martes) la ve en la ventana.
  const history = [filing("2026-09-03"), filing("2025-12-03"), filing("2025-09-04")];
  const e = earningsOf("CRM", history, "2026-12-01");
  assertEquals(e?.kind, "estimated");
  assertEquals(e?.url, null);
  assertEquals(e?.date, "2026-12-02");
  // Una semana antes todavía no entra en la ventana.
  assertEquals(earningsOf("CRM", history, "2026-11-23"), null);
  // Sin historial de resultados no se inventa nada.
  assertEquals(earningsOf("CRM", [], "2026-12-01"), null);
  // Si ya reportó, gana lo confirmado.
  assertEquals(earningsOf("CRM", [filing("2026-11-30"), ...history], "2026-12-01")?.kind, "reported");
});

// Cobertura de noticias por mercado (spec 2026-11-20-brief-diario-tech.md §8).
// Criterio de lanzamiento, no de desarrollo: mide cuántas posiciones tienen
// titular antes de prometer el "por qué" en un mercado.
//
//   cd supabase/functions
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//     deno run --allow-net --allow-env scripts/news_coverage.ts [--limit=300] [--weights]
//
// - Lee SOLO los símbolos distintos de `positions` con quantity > 0 (nunca el
//   user_id: la consulta pide solo `ticker`, y con --weights solo cuenta cuántos
//   usuarios tienen cada uno, agregado). Corre `headlinesByTicker`
//   respetando el limitador global de GDELT (1 pedido cada ~5,5 s: 100 símbolos
//   son ~10 lotes, un minuto). Escribe en la caché de titulares, no toca nada más.
// - Contra producción, solo con OK explícito del usuario (modo lectura).
// - Por mercado (sufijo de la bolsa; sin sufijo = EE. UU.) reporta: % de
//   símbolos con al menos 1 titular en 48 h y en 7 días, mezcla de idiomas,
//   medios más frecuentes y tickers sin nombre de prensa.
// - Umbral para prometer el "por qué" en un mercado: >= 60 % de las posiciones
//   con más peso con titular en 48 h (supuesto, lo valida data). Con --weights
//   el 60 % se calcula sobre los 10 símbolos más tenidos del mercado.

import { defaultDeps } from "../_shared/common.ts";
import { headlinesByTicker } from "../_shared/gdelt.ts";

const arg = (name: string) => Deno.args.find((a) => a.startsWith(`--${name}=`))?.split("=")[1];
const limit = Number(arg("limit") ?? 300);
const weights = Deno.args.includes("--weights");
const hours = (h: number) => Date.now() - h * 3600_000;

const deps = defaultDeps();
const { data, error } = await deps.db.from("positions").select("ticker").gt("quantity", 0).limit(50_000);
if (error) throw new Error(`positions: ${error.message}`);

const holders = new Map<string, number>();
for (const r of data as { ticker: string }[]) {
  const s = r.ticker.toUpperCase();
  holders.set(s, (holders.get(s) ?? 0) + 1);
}
const symbols = [...holders.entries()].sort((a, b) => b[1] - a[1]).slice(0, limit).map(([s]) => s);
console.log(`símbolos distintos: ${holders.size}; se miden ${symbols.length}`);

const marketOf = (s: string) => {
  if (/-(USD|USDT|EUR)$/.test(s)) return "cripto";
  const suffix = /\.([A-Z]{1,3})$/.exec(s)?.[1];
  return !suffix || ["A", "B", "C"].includes(suffix) ? "US" : `.${suffix}`;
};

const day = new Date().toISOString().slice(0, 10);
const byTicker: Record<string, Awaited<ReturnType<typeof headlinesByTicker>>["byTicker"][string]> = {};
const unnamed = new Set<string>();
let pending = symbols;
for (let round = 0; pending.length > 0 && round < 40; round++) {
  const r = await headlinesByTicker(deps, pending, day, { maxBatches: 3 });
  Object.assign(byTicker, r.byTicker);
  r.unnamed.forEach((s) => unnamed.add(s));
  const still = r.pending.filter((s) => !(s in byTicker) || r.pending.includes(s));
  if (still.length === pending.length && r.fetched === 0) {
    console.error("GDELT no da turno: se corta con lo medido");
    break;
  }
  pending = still;
}

type Stat = { total: number; h48: number; d7: number; langs: Record<string, number>; outlets: Record<string, number>; unnamed: string[]; top: { s: string; ok: boolean }[] };
const stats = new Map<string, Stat>();
for (const s of symbols) {
  const m = marketOf(s);
  const st = stats.get(m) ?? { total: 0, h48: 0, d7: 0, langs: {}, outlets: {}, unnamed: [], top: [] };
  const items = byTicker[s] ?? [];
  const in48 = items.some((h) => Date.parse(h.published_at) >= hours(48));
  const in7 = items.some((h) => Date.parse(h.published_at) >= hours(24 * 7));
  st.total++;
  if (in48) st.h48++;
  if (in7) st.d7++;
  for (const h of items) {
    st.langs[h.language ?? "?"] = (st.langs[h.language ?? "?"] ?? 0) + 1;
    st.outlets[h.source] = (st.outlets[h.source] ?? 0) + 1;
  }
  if (unnamed.has(s)) st.unnamed.push(s);
  if (st.top.length < 10) st.top.push({ s, ok: in48 });
  stats.set(m, st);
}

const pct = (n: number, d: number) => (d === 0 ? "n/a" : `${Math.round((n / d) * 100)} %`);
console.log(`\nmercado | símbolos | con titular 48 h | 7 d | top-10 con titular 48 h | veredicto`);
for (const [m, st] of [...stats.entries()].sort((a, b) => b[1].total - a[1].total)) {
  const topOk = st.top.filter((t) => t.ok).length / Math.max(st.top.length, 1);
  const verdict = topOk >= 0.6 ? "promete el por qué" : "cubrir con temas";
  console.log(`${m} | ${st.total} | ${pct(st.h48, st.total)} | ${pct(st.d7, st.total)} | ${Math.round(topOk * 100)} % | ${verdict}`);
  const top = Object.entries(st.outlets).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([k, v]) => `${k} (${v})`).join(", ");
  console.log(`   idiomas: ${JSON.stringify(st.langs)}; medios: ${top || "—"}`);
  if (st.unnamed.length > 0) console.log(`   sin nombre de prensa: ${st.unnamed.slice(0, 20).join(", ")}${st.unnamed.length > 20 ? "…" : ""}`);
  if (weights) console.log(`   usuarios por símbolo (top 3): ${st.top.slice(0, 3).map((t) => `${t.s}=${holders.get(t.s)}`).join(", ")}`);
}

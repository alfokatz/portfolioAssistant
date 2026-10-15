// SEC EDGAR para Porty: presentaciones, resultados y fundamentals de
// empresas que presentan ante la SEC. Reemplaza a Finnhub (`/stock/metric`,
// `/stock/earnings`, `/calendar/earnings`, sin uso comercial en el plan
// gratis) cuando `app_config.news_provider = v2`.
//
// La app llama GET /functions/v1/sec/<endpoint>?ticker=XXX con su JWT:
//   - filings       → últimas presentaciones relevantes (8-K, 10-Q, 10-K, 6-K, 20-F)
//   - earnings      → último comunicado de resultados (texto recortado para
//                     que el modelo lo resuma), trimestres y próximo reporte
//                     ESTIMADO (EDGAR no publica un calendario)
//   - fundamentals  → set acotado de XBRL (ingresos, resultado, EPS,
//                     márgenes, deuda, caja, acciones), últimos 4 trimestres
//                     y 3 años
//
// Datos de Gold: el plan se valida acá (`gold_data_allowed`). Los datos y
// el comunicado están en inglés; el modelo responde en el idioma del usuario.

import { bearer, corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { goldAllowed } from "../_shared/data_cache.ts";
import { companyPageUrl, earningsReleases, isNotable, itemLabels, normalizeTicker, SecUnavailable } from "../_shared/sec.ts";
import {
  companyFilings,
  companyFundamentals,
  foreignResults,
  nextReportFrom,
  pressReleaseOf,
  resolveCik,
} from "../_shared/sec_data.ts";

export const config = {
  ratePerMinute: 60,
  maxFilings: 15,
};

const endpoints = new Set(["filings", "earnings", "fundamentals"]);

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return typedError(405, "method_not_allowed", "GET only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  const url = new URL(req.url);
  const endpoint = url.pathname.replace(/^.*\/sec\/?/, "").replace(/\/$/, "");
  if (!endpoints.has(endpoint)) return typedError(404, "endpoint_not_allowed", `${endpoint} not allowed`);
  const raw = url.searchParams.get("ticker") ?? "";
  if (!/^[A-Za-z0-9.\-]{1,10}$/.test(raw)) return typedError(400, "invalid_ticker", "ticker expected");
  const ticker = normalizeTicker(raw);

  if (!(await goldAllowed(deps, userId, [ticker]))) {
    return typedError(403, "plan_required", "Gold required", { required_plan: "gold" });
  }

  const rate = await deps.db.rpc("rate_limit_hit", {
    p_user_id: userId,
    p_bucket: "sec",
    p_per_minute: config.ratePerMinute,
  });
  if (rate.data === false) return typedError(429, "rate_limited", "Too many requests");

  const started = Date.now();
  try {
    const row = await resolveCik(deps, ticker);
    if (!row) {
      log(endpoint, "not_found", started);
      return json(200, {
        status: "not_found",
        ticker,
        message: `No hay presentaciones ante la SEC para ${ticker}.`,
      });
    }
    const body = endpoint === "filings"
      ? await filingsBody(deps, ticker, row.cik)
      : endpoint === "earnings"
      ? await earningsBody(deps, ticker, row.cik)
      : await fundamentalsBody(deps, ticker, row.cik);
    log(endpoint, body.cache, started);
    return json(200, body.body, { "x-cache": body.cache });
  } catch (e) {
    console.error("[sec]", endpoint, ticker, e);
    log(endpoint, "error", started);
    if (e instanceof SecUnavailable) return typedError(502, "upstream_unavailable", "SEC unavailable");
    return typedError(500, "internal", "Unexpected error");
  }
}

const source = (cik: string) => ({ name: "SEC EDGAR", url: companyPageUrl(cik) });

type Built = { body: Record<string, unknown>; cache: string };

/// "hit" solo si todo salió de la caché; si algo fue a la SEC, "miss".
const worst = (...c: string[]) => c.includes("stale") ? "stale" : c.every((x) => x === "hit") ? "hit" : "miss";

async function filingsBody(deps: Deps, ticker: string, cik: string): Promise<Built> {
  const { value, cache } = await companyFilings(deps, cik);
  return {
    cache,
    body: {
      status: "ok",
      ticker,
      company_name: value.company.name,
      industry: value.company.industry,
      filings: value.filings.filter(isNotable).slice(0, config.maxFilings).map((f) => ({
        form: f.form,
        filed: f.filed,
        report_date: f.report_date,
        items: f.items.filter((i) => itemLabels[i]).map((i) => ({ code: i, label: itemLabels[i] })),
        url: f.url,
        index_url: f.index_url,
      })),
      source: source(cik),
    },
  };
}

async function earningsBody(deps: Deps, ticker: string, cik: string): Promise<Built> {
  const filings = await companyFilings(deps, cik);
  const { company } = filings.value;
  const facts = await companyFundamentals(deps, cik);
  const today = new Date(deps.now()).toISOString().slice(0, 10);

  let release = null;
  let foreignDates: string[] = [];
  let releaseCache = "hit";
  if (company.filer === "domestic") {
    const latest = earningsReleases(filings.value.filings)[0];
    if (latest) {
      const r = await pressReleaseOf(deps, cik, latest);
      release = r.value;
      releaseCache = r.cache;
    }
  } else {
    const r = await foreignResults(deps, cik);
    release = r.value.release;
    foreignDates = r.value.release_dates;
    releaseCache = r.cache;
  }
  const next = nextReportFrom(company, filings.value.filings, foreignDates, today);
  const f = facts.value;

  return {
    cache: worst(filings.cache, facts.cache, releaseCache),
    body: {
      status: release || f?.quarters.length || f?.years.length ? "ok" : "empty",
      ticker,
      company_name: company.name,
      filer: company.filer,
      currency: f?.currency ?? null,
      latest_release: release,
      quarters: f?.quarters ?? [],
      years: f?.years ?? [],
      next_report: next ? { date: next.date, estimated: true, basis: next.basis } : null,
      source: source(cik),
    },
  };
}

async function fundamentalsBody(deps: Deps, ticker: string, cik: string): Promise<Built> {
  const filings = await companyFilings(deps, cik);
  const facts = await companyFundamentals(deps, cik);
  const { company } = filings.value;
  return {
    cache: worst(filings.cache, facts.cache),
    body: facts.value
      ? {
        status: "ok",
        ticker,
        company_name: company.name,
        industry: company.industry,
        filer: company.filer,
        fiscal_year_end: company.fiscal_year_end,
        ...facts.value,
        source: source(cik),
      }
      : { status: "empty", ticker, company_name: company.name, source: source(cik) },
  };
}

/// Una línea por pedido (sin usuario) para medir caché y latencia.
function log(endpoint: string, cache: string, started: number) {
  console.log(JSON.stringify({ fn: "sec", endpoint, cache, ms: Date.now() - started }));
}

// "Qué dicen los super investors" de una semana bursátil, para el informe
// semanal de Porty. Es igual para todos los usuarios: se arma una vez y se
// cachea por semana (investor_pulse_cache).
//
// La app llama GET /functions/v1/investor-pulse?week=YYYY-MM-DD (el lunes de
// la semana cubierta) con su JWT.

import { bearer, corsHeaders, type Deps, json, sleep, typedError } from "../_shared/common.ts";
import {
  documentUrl,
  type FilingAction,
  type FilingItem,
  filingIndexUrl,
  googleNewsUrl,
  type Investor,
  type NewsItem,
  needsDocument,
  parseForm4,
  parseGoogleRss,
  parseSchedule13,
  type PulseItem,
  recentFilings,
  selectNews,
  submissionsUrl,
  tickerMap,
  tickerMapUrl,
  type Week,
  weekOf,
} from "./sources.ts";

export const config = {
  /// Mientras la semana está "fresca" (los Form 4 llegan hasta 2 días
  /// hábiles después de la operación) se vuelve a armar cada 6 h.
  freshSeconds: 6 * 60 * 60,
  /// Pasado el martes siguiente ya no cambia: una vez por semana alcanza.
  settledSeconds: 7 * 24 * 60 * 60,
  maxWeeksBack: 12,
  ratePerMinute: 20,
  /// La SEC pide ≤ 10 pedidos/s por IP; con esto quedamos debajo de 7.
  secDelayMs: 150,
  /// Documentos de presentaciones a bajar por armado (cada uno es un pedido).
  maxDocuments: 30,
  maxFilingsPerInvestor: 3,
  maxItems: 30,
  googleConcurrency: 4,
};

type Built = { items: PulseItem[]; anySourceOk: boolean };

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return typedError(405, "method_not_allowed", "GET only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  const param = new URL(req.url).searchParams.get("week") ?? "";
  const week = weekOf(param);
  if (!week) return typedError(400, "invalid_week", "week must be a Monday YYYY-MM-DD");
  const today = new Date(deps.now()).toISOString().slice(0, 10);
  const oldest = new Date(deps.now() - config.maxWeeksBack * 7 * 86_400_000)
    .toISOString().slice(0, 10);
  if (week.monday > today || week.monday < oldest) {
    return typedError(400, "invalid_week", "week out of range");
  }

  const allowed = await deps.db.rpc("rate_limit_hit", {
    p_user_id: userId,
    p_bucket: "investor_pulse",
    p_per_minute: config.ratePerMinute,
  });
  if (allowed.data === false) return typedError(429, "rate_limited", "Too many requests");

  const { data: cached } = await deps.db
    .from("investor_pulse_cache")
    .select("items, fetched_at")
    .eq("week_start", week.monday)
    .maybeSingle();
  if (cached && isFresh(cached.fetched_at, week, deps.now())) {
    log(week, "hit");
    return reply(week, cached.items, cached.fetched_at, "hit");
  }

  const { data: investors, error } = await deps.db
    .from("super_investors")
    .select("id, display_name, organization, kind, search_terms, ciks, sort")
    .eq("active", true)
    .order("sort");
  if (error) return typedError(500, "db_error", error.message);

  const built = await build(deps, week, (investors ?? []) as Investor[]);
  if (!built.anySourceOk) {
    if (cached) {
      log(week, "stale");
      return reply(week, cached.items, cached.fetched_at, "stale");
    }
    log(week, "error");
    return typedError(502, "upstream_unavailable", "News and SEC unavailable");
  }

  const fetchedAt = new Date(deps.now()).toISOString();
  const { error: upsertError } = await deps.db.from("investor_pulse_cache").upsert({
    week_start: week.monday,
    items: built.items,
    fetched_at: fetchedAt,
  });
  if (upsertError) console.error("investor_pulse_cache upsert failed", upsertError.message);
  log(week, "miss", built.items.length);
  return reply(week, built.items, fetchedAt, "miss");
}

function reply(week: Week, items: unknown, fetchedAt: string, cache: string): Response {
  return json(200, { week_start: week.monday, fetched_at: fetchedAt, items }, { "x-cache": cache });
}

/// Una semana se considera asentada cuando el armado es posterior al
/// miércoles siguiente (los Form 4 del viernes ya llegaron).
export function isFresh(fetchedAt: string, week: Week, now: number): boolean {
  const fetched = Date.parse(fetchedAt);
  const settledFrom = Date.parse(`${week.saturday}T00:00:00Z`) + 4 * 86_400_000;
  const ttl = fetched >= settledFrom ? config.settledSeconds : config.freshSeconds;
  return (now - fetched) / 1000 < ttl;
}

export async function build(deps: Deps, week: Week, investors: Investor[]): Promise<Built> {
  const [news, filings] = await Promise.all([
    newsFor(deps, week, investors),
    filingsFor(deps, week, investors),
  ]);
  // Primero las presentaciones (dato duro), después las noticias; dentro de
  // cada grupo, en el orden de la tabla.
  const order = new Map(investors.map((i) => [i.id, i.sort]));
  const bySort = (a: PulseItem, b: PulseItem) =>
    (order.get(a.investor_id) ?? 0) - (order.get(b.investor_id) ?? 0) ||
    b.date.localeCompare(a.date);
  const items = [...filings.items.sort(bySort), ...news.items.sort(bySort)]
    .slice(0, config.maxItems)
    .map((item, i) => ({ ...item, id: `i${i + 1}` }));
  return { items, anySourceOk: news.ok || filings.ok };
}

function base(investor: Investor) {
  return {
    id: "",
    investor_id: investor.id,
    investor_name: investor.display_name,
    organization: investor.organization,
    voice: investor.kind,
  };
}

async function newsFor(
  deps: Deps,
  week: Week,
  investors: Investor[],
): Promise<{ items: NewsItem[]; ok: boolean }> {
  let ok = false;
  const results = await mapLimit(investors, config.googleConcurrency, async (investor) => {
    try {
      const res = await deps.fetch(googleNewsUrl(investor, week), {
        headers: { "User-Agent": "Mozilla/5.0 (Porty)" },
      });
      if (res.status !== 200) {
        await res.body?.cancel();
        return [];
      }
      ok = true;
      return selectNews(parseGoogleRss(await res.text()), investor, week).map(
        (h): NewsItem => ({
          ...base(investor),
          type: "news",
          headline: h.headline,
          source: h.source,
          url: h.url,
          date: h.published.toISOString().slice(0, 10),
        }),
      );
    } catch {
      return [];
    }
  });
  return { items: results.flat(), ok };
}

async function filingsFor(
  deps: Deps,
  week: Week,
  investors: Investor[],
): Promise<{ items: FilingItem[]; ok: boolean }> {
  const userAgent = deps.env("SEC_USER_AGENT");
  if (!userAgent) {
    // La SEC exige identificarse; sin contacto configurado, solo noticias.
    console.warn("SEC_USER_AGENT not set: skipping SEC filings");
    return { items: [], ok: false };
  }
  let ok = false;
  let documents = 0;
  let tickers: Map<string, string> | null = null;
  const sec = async (url: string) => {
    await sleep(config.secDelayMs);
    const res = await deps.fetch(url, {
      headers: { "User-Agent": userAgent, "Accept": "application/json, text/xml" },
    });
    if (res.status !== 200) {
      await res.body?.cancel();
      return null;
    }
    return res;
  };

  const items: FilingItem[] = [];
  for (const investor of investors) {
    // Compras/ventas por emisora: varios Form 4 de la misma semana se suman.
    const trades = new Map<string, FilingItem>();
    const others: FilingItem[] = [];
    for (const cik of investor.ciks) {
      let filings;
      try {
        const res = await sec(submissionsUrl(cik));
        if (!res) continue;
        filings = recentFilings(await res.json(), cik, week);
        ok = true;
      } catch {
        continue;
      }
      for (const f of filings) {
        const item: FilingItem = {
          ...base(investor),
          type: "filing",
          form: f.form,
          action: "quarterly_portfolio",
          issuer_name: null,
          issuer_ticker: null,
          shares: null,
          period: null,
          date: f.filingDate,
          url: filingIndexUrl(f),
        };
        if (!needsDocument(f)) {
          others.push({ ...item, period: f.reportDate });
          continue;
        }
        if (documents >= config.maxDocuments) continue;
        documents++;
        let xml: string;
        try {
          const res = await sec(documentUrl(f));
          if (!res) continue;
          xml = await res.text();
        } catch {
          continue;
        }
        if (f.form === "4") {
          const parsed = parseForm4(xml, cik);
          if (!parsed) continue;
          const action: FilingAction = parsed.bought >= parsed.sold ? "buy" : "sell";
          const key = `${parsed.issuerTicker ?? parsed.issuerName}|${action}`;
          const shares = action === "buy" ? parsed.bought - parsed.sold : parsed.sold - parsed.bought;
          const prev = trades.get(key);
          trades.set(key, {
            ...item,
            action,
            issuer_name: parsed.issuerName,
            issuer_ticker: parsed.issuerTicker,
            shares: (prev?.shares ?? 0) + shares,
            date: prev && prev.date > item.date ? prev.date : item.date,
            url: prev && prev.date > item.date ? prev.url : item.url,
          });
        } else {
          const parsed = parseSchedule13(xml);
          if (!parsed.issuerName && !parsed.issuerCik) continue;
          if (parsed.issuerCik && tickers === null) {
            tickers = new Map();
            try {
              const res = await sec(tickerMapUrl);
              if (res) tickers = tickerMap(await res.json());
            } catch {
              // sin ticker: igual se muestra la empresa por nombre
            }
          }
          others.push({
            ...item,
            action: f.form.endsWith("/A") ? "stake_update" : "stake",
            issuer_name: parsed.issuerName,
            issuer_ticker: parsed.issuerCik ? tickers?.get(parsed.issuerCik) ?? null : null,
          });
        }
      }
    }
    items.push(...[...trades.values(), ...others].slice(0, config.maxFilingsPerInvestor));
  }
  return { items, ok };
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out = new Array<R>(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (next < items.length) {
        const i = next++;
        out[i] = await fn(items[i]);
      }
    }),
  );
  return out;
}

function log(week: Week, cache: "hit" | "miss" | "stale" | "error", items?: number) {
  console.log(JSON.stringify({ fn: "investor-pulse", week: week.monday, cache, items }));
}

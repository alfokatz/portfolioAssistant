// Caché compartida de las fuentes de datos con uso comercial (SEC, búsqueda
// web de noticias, GDELT): tabla `data_source_cache`, una fila por clave
// ("sec:facts:0000320193", "news:nvda|es"…). Igual que el proxy de Finnhub:
// lo que pidió un usuario le sirve a todos, y si la fuente falla se sirve el
// último dato aunque esté vencido.

import type { Deps } from "./common.ts";

export type Cached<T> = { body: T; ageSeconds: number };

export async function readCache<T>(deps: Pick<Deps, "db" | "now">, key: string): Promise<Cached<T> | null> {
  const { data } = await deps.db
    .from("data_source_cache")
    .select("body, fetched_at")
    .eq("cache_key", key)
    .maybeSingle();
  if (!data) return null;
  return {
    body: data.body as T,
    ageSeconds: (deps.now() - Date.parse(data.fetched_at as string)) / 1000,
  };
}

export async function writeCache(deps: Pick<Deps, "db" | "now">, key: string, body: unknown): Promise<void> {
  const { error } = await deps.db.from("data_source_cache").upsert({
    cache_key: key,
    body,
    fetched_at: new Date(deps.now()).toISOString(),
  });
  if (error) console.error("data_source_cache upsert failed", key, error.message);
}

export type CacheOutcome = "hit" | "miss" | "stale" | "error";

/// Lee [key]; si está vigente (< [ttlSeconds]) lo devuelve. Si no, corre
/// [load]: con resultado lo guarda (si [shouldStore] lo acepta); si [load]
/// tira, sirve el dato vencido si lo hay.
export async function cached<T>(
  deps: Pick<Deps, "db" | "now">,
  key: string,
  ttlSeconds: number,
  load: () => Promise<T>,
  shouldStore: (value: T) => boolean = () => true,
): Promise<{ value: T; cache: CacheOutcome }> {
  const hit = await readCache<T>(deps, key);
  if (hit && hit.ageSeconds < ttlSeconds) return { value: hit.body, cache: "hit" };
  try {
    const value = await load();
    if (shouldStore(value)) await writeCache(deps, key, value);
    return { value, cache: "miss" };
  } catch (e) {
    if (hit) return { value: hit.body, cache: "stale" };
    throw e;
  }
}

/// Plan validado en el servidor: Gold, la cortesía semanal de ese ticker o
/// un informe semanal en curso (RPC `gold_data_allowed`).
export async function goldAllowed(
  deps: Pick<Deps, "db">,
  userId: string,
  tickers: string[],
): Promise<boolean> {
  if (tickers.length === 0) {
    const { data } = await deps.db.rpc("gold_data_allowed", { p_user_id: userId, p_ticker: null });
    return data === true;
  }
  // Una RPC por ticker, a la vez (en serie sumaban un viaje a la base cada uno).
  const checks = await Promise.all(
    tickers.map((ticker) => deps.db.rpc("gold_data_allowed", { p_user_id: userId, p_ticker: ticker })),
  );
  return checks.every(({ data }) => data === true);
}

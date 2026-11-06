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

/// Titulares y contexto de noticias (`headlines`, `news-context`): lo de
/// [goldAllowed] más Premium con el ticker en cartera, solo con el camino v2
/// (RPC `news_data_allowed`). [tickers] va como llegó en el pedido, antes de
/// normalizarlo (así coincide con `positions.ticker`: sufijos .BA, -USD); sin
/// tickers solo pasa lo de Gold (informe, cortesía). Si el caller normaliza,
/// [normalize] mantiene el chequeo de la cortesía semanal, que se guardó con
/// el ticker normalizado.
export async function newsAllowed(
  deps: Pick<Deps, "db">,
  userId: string,
  tickers: string[],
  normalize?: (ticker: string) => string,
): Promise<boolean> {
  if (tickers.length === 0) {
    const { data } = await deps.db.rpc("news_data_allowed", { p_user_id: userId, p_ticker: null });
    return data === true;
  }
  const checks = await Promise.all(tickers.map(async (ticker) => {
    const { data } = await deps.db.rpc("news_data_allowed", { p_user_id: userId, p_ticker: ticker });
    if (data === true) return true;
    const normalized = normalize?.(ticker);
    if (!normalized || normalized === ticker) return false;
    const alt = await deps.db.rpc("gold_data_allowed", { p_user_id: userId, p_ticker: normalized });
    return alt.data === true;
  }));
  return checks.every(Boolean);
}

/// El `names` y la `question` que manda el cliente solo se respetan si el
/// permiso NO viene de tener el ticker en cartera (Gold, cortesía de ese
/// ticker, informe en curso: `gold_data_allowed`). Entran en la búsqueda y
/// en una caché que ve todo el mundo: un Premium no puede usarlos para
/// envenenarla ni para pedir noticias de otra empresa. Para Premium el
/// servidor resuelve el nombre y la pregunta se ignora.
export async function clientTextTrusted(
  deps: Pick<Deps, "db">,
  userId: string,
  tickers: string[],
): Promise<boolean> {
  const list = tickers.length === 0 ? [null] : tickers;
  const checks = await Promise.all(
    list.map((t) => deps.db.rpc("gold_data_allowed", { p_user_id: userId, p_ticker: t })),
  );
  return checks.every(({ data }) => data === true);
}

/// true si TODOS los [tickers] (como vinieron en el pedido) están en
/// `positions` del usuario con cantidad > 0. Es el permiso de los conteos
/// (`headlines?count_only=1`, `sec?endpoint=earnings_count`): valen para
/// cualquier plan porque no devuelven contenido, solo un número.
export async function allHeld(
  deps: Pick<Deps, "db">,
  userId: string,
  tickers: string[],
): Promise<boolean> {
  if (tickers.length === 0) return false;
  const { data, error } = await deps.db.from("positions").select("ticker").eq("user_id", userId).gt("quantity", 0);
  if (error || !data) return false;
  const held = new Set((data as { ticker: string }[]).map((r) => r.ticker.toUpperCase()));
  return tickers.every((t) => held.has(t.toUpperCase()));
}

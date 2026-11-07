// Cliente de la API de Binance (spot), solo lo que hace falta para leer:
// permisos de la clave, saldos, precios y operaciones propias. Las rutas
// con clave van firmadas (HMAC-SHA256 del query string con el secreto).
//
// Docs: https://developers.binance.com/docs/binance-spot-api-docs/rest-api
// y https://developers.binance.com/docs/wallet/account/api-key-permission

export const binanceConfig = {
  defaultBaseUrl: "https://api.binance.com",
  recvWindow: 10_000,
};

export type BinanceKeys = { apiKey: string; apiSecret: string };

/// Errores tipados para la app.
/// - invalid_key: la clave no existe, se borró o no tiene permiso (-2015).
/// - region_blocked: Binance no atiende desde la región del servidor (451).
/// - rate_limited: 429/418.
/// - unavailable: red o 5xx.
export type BinanceErrorType = "invalid_key" | "region_blocked" | "rate_limited" | "unavailable";

export class BinanceError extends Error {
  constructor(readonly type: BinanceErrorType, readonly status = 0) {
    super(`binance_${type}`);
  }
}

export type ApiRestrictions = Record<string, unknown>;

export type Balance = { asset: string; free: number; locked: number };

export type Trade = {
  price: number;
  qty: number;
  commission: number;
  commissionAsset: string;
  time: number;
  isBuyer: boolean;
};

export async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export class BinanceClient {
  constructor(
    private readonly fetchFn: typeof fetch,
    private readonly now: () => number,
    private readonly baseUrl = binanceConfig.defaultBaseUrl,
  ) {}

  /// Lo que la clave puede hacer.
  apiRestrictions(keys: BinanceKeys): Promise<ApiRestrictions> {
    return this.signed("/sapi/v1/account/apiRestrictions", {}, keys) as Promise<ApiRestrictions>;
  }

  async balances(keys: BinanceKeys): Promise<Balance[]> {
    const body = await this.signed("/api/v3/account", { omitZeroBalances: "true" }, keys);
    const list = (body as { balances?: unknown[] })?.balances;
    if (!Array.isArray(list)) throw new BinanceError("unavailable");
    return (list as Record<string, unknown>[])
      .map((b) => ({ asset: String(b.asset ?? ""), free: Number(b.free ?? 0), locked: Number(b.locked ?? 0) }))
      .filter((b) => b.asset && (b.free > 0 || b.locked > 0));
  }

  /// Último precio de todos los pares: "BTCUSDT" → 60000.
  async prices(): Promise<Map<string, number>> {
    const body = await this.request("/api/v3/ticker/price", new URLSearchParams(), null);
    const out = new Map<string, number>();
    if (!Array.isArray(body)) return out;
    for (const p of body as Record<string, unknown>[]) {
      const price = Number(p.price);
      if (typeof p.symbol === "string" && price > 0) out.set(p.symbol, price);
    }
    return out;
  }

  /// Operaciones propias en [pair] ("BTCUSDT"), las últimas 1000.
  async trades(pair: string, keys: BinanceKeys): Promise<Trade[]> {
    const body = await this.signed("/api/v3/myTrades", { symbol: pair, limit: "1000" }, keys);
    if (!Array.isArray(body)) return [];
    return (body as Record<string, unknown>[]).map((t) => ({
      price: Number(t.price),
      qty: Number(t.qty),
      commission: Number(t.commission ?? 0),
      commissionAsset: String(t.commissionAsset ?? ""),
      time: Number(t.time),
      isBuyer: t.isBuyer === true,
    }));
  }

  private async signed(path: string, params: Record<string, string>, keys: BinanceKeys): Promise<unknown> {
    const query = new URLSearchParams({
      ...params,
      recvWindow: String(binanceConfig.recvWindow),
      timestamp: String(this.now()),
    });
    query.set("signature", await hmacHex(keys.apiSecret, query.toString()));
    return this.request(path, query, keys.apiKey);
  }

  private async request(path: string, query: URLSearchParams, apiKey: string | null): Promise<unknown> {
    const qs = query.toString();
    let res: Response;
    try {
      res = await this.fetchFn(`${this.baseUrl}${path}${qs ? `?${qs}` : ""}`, {
        headers: apiKey ? { "X-MBX-APIKEY": apiKey } : {},
      });
    } catch {
      throw new BinanceError("unavailable");
    }
    if (res.ok) return await res.json();
    let code: number | null = null;
    try {
      code = Number((await res.json())?.code);
    } catch {
      // sin body
    }
    if (res.status === 451) throw new BinanceError("region_blocked", 451);
    if (res.status === 429 || res.status === 418) throw new BinanceError("rate_limited", res.status);
    if (res.status === 401 || code === -2015 || code === -2014 || code === -1022) {
      throw new BinanceError("invalid_key", res.status);
    }
    throw new BinanceError("unavailable", res.status);
  }
}

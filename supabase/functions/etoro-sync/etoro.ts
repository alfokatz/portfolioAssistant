// Cliente de eToro: SSO (OpenID Connect) + Public API de SOLO LECTURA.
//
// - La Public API se usa únicamente con GET: este módulo no tiene ninguna
//   forma de mandar una orden, cerrar o modificar nada.
// - Los tokens nunca se loguean ni se devuelven en un error.
//
// Doc: https://api-portal.etoro.com/core/getting-started/sso-oauth

import { createLocalJWKSet, jwtVerify, type JSONWebKeySet } from "npm:jose@5";

export const etoroConfig = {
  issuer: "https://www.etoro.com",
  discoveryUrl: "https://www.etoro.com/.well-known/openid-configuration",
  // Valores del discovery a la fecha (2026-10-08); se usan si el discovery no
  // responde.
  fallback: {
    authorizationEndpoint: "https://www.etoro.com/sso",
    tokenEndpoint: "https://www.etoro.com/api/sso/v1/token",
    revocationEndpoint: "https://www.etoro.com/api/sso/v1/token/revoke",
    jwksUri: "https://www.etoro.com/.well-known/jwks.json",
  },
  apiBase: "https://public-api.etoro.com",
  requestTimeoutMs: 15_000,
  /// `/market-data/instruments` rechaza lotes grandes con 413/414.
  instrumentBatchSizes: [50, 25],
  historyPageSize: 100,
  historyMaxPages: 20,
};

export type EtoroTokens = {
  accessToken: string;
  refreshToken: string | null;
  /// epoch ms
  expiresAt: number;
  scope: string[];
};

export type EtoroErrorType =
  | "invalid_grant" // refresh token vencido o revocado: hay que reconectar
  | "unauthorized" // 401 de la API
  | "forbidden" // 403 de la API (scope insuficiente)
  | "rate_limited"
  | "unavailable" // 5xx, timeout, red
  | "bad_response"
  | "config";

export class EtoroError extends Error {
  constructor(
    readonly type: EtoroErrorType,
    message: string,
    readonly status?: number,
    readonly retryAfterSeconds?: number,
  ) {
    super(message);
    this.name = "EtoroError";
  }
}

export type EtoroCredentials = {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
};

/// `real` en producción; `demo` para probar de punta a punta con una cuenta
/// de dinero virtual (staging). Cambia los endpoints y el scope de lectura.
export type EtoroEnvironment = "real" | "demo";

export function etoroEnvironment(value: string | undefined): EtoroEnvironment {
  return value === "demo" ? "demo" : "real";
}

/// Solo lectura: identidad + portfolio/historial de la cuenta.
export function readScope(env: EtoroEnvironment): string {
  return env === "demo" ? "etoro-public:demo:read" : "etoro-public:real:read";
}

export function requestedScopes(env: EtoroEnvironment): string[] {
  return ["openid", readScope(env)];
}

const apiPaths = {
  real: { pnl: "/api/v1/trading/info/real/pnl", history: "/api/v1/trading/info/trade/history" },
  demo: { pnl: "/api/v1/trading/info/demo/pnl", history: "/api/v1/trading/info/trade/demo/history" },
} as const;

type Endpoints = typeof etoroConfig.fallback;

/// Discovery + JWKS cacheados por proceso (la doc pide resolverlos en
/// runtime: las claves rotan).
let discoveryCache: { at: number; endpoints: Endpoints } | null = null;
let jwksCache: { at: number; jwks: JSONWebKeySet } | null = null;
const discoveryTtlMs = 60 * 60 * 1000;

/// Solo para tests.
export function resetEtoroCaches() {
  discoveryCache = null;
  jwksCache = null;
}

export class EtoroClient {
  constructor(
    private readonly fetchImpl: typeof fetch,
    private readonly credentials: EtoroCredentials,
    private readonly now: () => number,
    readonly environment: EtoroEnvironment = "real",
  ) {}

  // ── SSO ──────────────────────────────────────────────────────────────────

  async endpoints(): Promise<Endpoints> {
    if (discoveryCache && this.now() - discoveryCache.at < discoveryTtlMs) {
      return discoveryCache.endpoints;
    }
    try {
      const r = await this.timedFetch(etoroConfig.discoveryUrl, {});
      if (r.ok) {
        const d = await r.json();
        const endpoints: Endpoints = {
          authorizationEndpoint: d.authorization_endpoint ?? etoroConfig.fallback.authorizationEndpoint,
          tokenEndpoint: d.token_endpoint ?? etoroConfig.fallback.tokenEndpoint,
          revocationEndpoint: d.revocation_endpoint ?? etoroConfig.fallback.revocationEndpoint,
          jwksUri: d.jwks_uri ?? etoroConfig.fallback.jwksUri,
        };
        discoveryCache = { at: this.now(), endpoints };
        return endpoints;
      }
      await r.body?.cancel();
    } catch {
      // cae al fallback
    }
    return etoroConfig.fallback;
  }

  async authorizeUrl(params: { state: string; nonce: string; codeChallenge: string }): Promise<string> {
    const { authorizationEndpoint } = await this.endpoints();
    const url = new URL(authorizationEndpoint);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("client_id", this.credentials.clientId);
    url.searchParams.set("redirect_uri", this.credentials.redirectUri);
    url.searchParams.set("scope", requestedScopes(this.environment).join(" "));
    url.searchParams.set("state", params.state);
    url.searchParams.set("nonce", params.nonce);
    url.searchParams.set("code_challenge", params.codeChallenge);
    url.searchParams.set("code_challenge_method", "S256");
    return url.toString();
  }

  async exchangeCode(code: string, codeVerifier: string): Promise<{ tokens: EtoroTokens; idToken: string | null }> {
    const body = new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: this.credentials.redirectUri,
      code_verifier: codeVerifier,
    });
    const data = await this.tokenRequest(body);
    return { tokens: this.toTokens(data, null), idToken: typeof data.id_token === "string" ? data.id_token : null };
  }

  /// Refresca. Si eToro no devuelve un refresh token nuevo, se conserva el
  /// anterior; si lo devuelve (rotación), el viejo ya no sirve y el caller
  /// tiene que guardar el nuevo antes de usar el access token.
  async refresh(refreshToken: string): Promise<EtoroTokens> {
    const body = new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken });
    const data = await this.tokenRequest(body);
    return this.toTokens(data, refreshToken);
  }

  /// RFC 7009. Siempre "best effort": un token ya revocado da error y no
  /// importa.
  async revoke(token: string, hint: "refresh_token" | "access_token"): Promise<boolean> {
    try {
      const { revocationEndpoint } = await this.endpoints();
      const r = await this.timedFetch(revocationEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          Authorization: this.basicAuth(),
        },
        body: new URLSearchParams({ token, token_type_hint: hint }).toString(),
      });
      await r.body?.cancel();
      return r.ok;
    } catch {
      return false;
    }
  }

  /// Valida el ID token (firma RS256 contra el JWKS por `kid`, iss, aud, exp,
  /// nonce) y devuelve el `sub`. Falla cerrado.
  async verifyIdToken(idToken: string, expectedNonce: string): Promise<string> {
    const jwks = await this.jwks(false);
    let payload;
    try {
      ({ payload } = await jwtVerify(idToken, createLocalJWKSet(jwks), {
        issuer: etoroConfig.issuer,
        audience: this.credentials.clientId,
        algorithms: ["RS256"],
        clockTolerance: 30,
        currentDate: new Date(this.now()),
      }));
    } catch (e) {
      // Clave rotada: un `kid` desconocido obliga a refrescar el JWKS una vez.
      if ((e as { code?: string }).code === "ERR_JWKS_NO_MATCHING_KEY") {
        const fresh = await this.jwks(true);
        ({ payload } = await jwtVerify(idToken, createLocalJWKSet(fresh), {
          issuer: etoroConfig.issuer,
          audience: this.credentials.clientId,
          algorithms: ["RS256"],
          clockTolerance: 30,
          currentDate: new Date(this.now()),
        }));
      } else {
        throw new EtoroError("bad_response", "invalid id_token");
      }
    }
    if (payload.nonce !== expectedNonce) throw new EtoroError("bad_response", "id_token nonce mismatch");
    if (typeof payload.sub !== "string" || payload.sub === "") {
      throw new EtoroError("bad_response", "id_token without sub");
    }
    return payload.sub;
  }

  // ── Public API (solo GET) ────────────────────────────────────────────────

  async portfolio(
    accessToken: string,
  ): Promise<{ positions: Record<string, unknown>[]; creditUsd: number | null }> {
    const data = await this.get(accessToken, apiPaths[this.environment].pnl);
    const cp = (data as { clientPortfolio?: { positions?: unknown; credit?: unknown } })?.clientPortfolio;
    if (!cp || !Array.isArray(cp.positions)) throw new EtoroError("bad_response", "pnl without positions");
    // `credit`: saldo disponible para operar, en USD.
    const credit = typeof cp.credit === "number" && Number.isFinite(cp.credit) ? cp.credit : null;
    return { positions: cp.positions as Record<string, unknown>[], creditUsd: credit };
  }

  /// Operaciones cerradas desde [minDate] (YYYY-MM-DD), paginadas.
  async history(accessToken: string, minDate: string): Promise<Record<string, unknown>[]> {
    const all: Record<string, unknown>[] = [];
    for (let page = 1; page <= etoroConfig.historyMaxPages; page++) {
      const chunk = await this.get(accessToken, apiPaths[this.environment].history, {
        minDate,
        page: String(page),
        pageSize: String(etoroConfig.historyPageSize),
      });
      if (!Array.isArray(chunk)) throw new EtoroError("bad_response", "history is not a list");
      all.push(...(chunk as Record<string, unknown>[]));
      if (chunk.length < etoroConfig.historyPageSize) break;
    }
    return all;
  }

  async instruments(accessToken: string, ids: number[]): Promise<Record<string, unknown>[]> {
    const out: Record<string, unknown>[] = [];
    let sizeIndex = 0;
    let i = 0;
    while (i < ids.length) {
      const size = etoroConfig.instrumentBatchSizes[sizeIndex];
      const chunk = ids.slice(i, i + size);
      try {
        const data = await this.get(accessToken, "/api/v1/market-data/instruments", {
          // Coma literal: eToro rechaza `%2C`.
          instrumentIds: chunk.join(","),
        });
        const list = (data as { instrumentDisplayDatas?: unknown })?.instrumentDisplayDatas;
        if (Array.isArray(list)) out.push(...(list as Record<string, unknown>[]));
        i += size;
      } catch (e) {
        if (e instanceof EtoroError && (e.status === 413 || e.status === 414) &&
            sizeIndex < etoroConfig.instrumentBatchSizes.length - 1) {
          sizeIndex++;
          continue;
        }
        throw e;
      }
    }
    return out;
  }

  async instrumentTypes(accessToken: string): Promise<Map<number, string>> {
    const data = await this.get(accessToken, "/api/v1/market-data/instrument-types");
    const list = (data as { instrumentTypes?: { instrumentTypeID: number; instrumentTypeDescription: string }[] })
      ?.instrumentTypes ?? [];
    return new Map(list.map((t) => [t.instrumentTypeID, t.instrumentTypeDescription]));
  }

  async exchanges(accessToken: string): Promise<Map<number, string>> {
    const data = await this.get(accessToken, "/api/v1/market-data/exchanges");
    const list = (data as { exchangeInfo?: { exchangeID: number; exchangeDescription: string }[] })
      ?.exchangeInfo ?? [];
    return new Map(list.map((e) => [e.exchangeID, e.exchangeDescription]));
  }

  // ── internos ─────────────────────────────────────────────────────────────

  private async get(accessToken: string, path: string, query: Record<string, string> = {}): Promise<unknown> {
    // Query armada a mano: URLSearchParams codifica la coma como %2C.
    const qs = Object.entries(query)
      .map(([k, v]) => `${encodeURIComponent(k)}=${k === "instrumentIds" ? v : encodeURIComponent(v)}`)
      .join("&");
    const url = `${etoroConfig.apiBase}${path}${qs ? `?${qs}` : ""}`;
    let r: Response;
    try {
      r = await this.timedFetch(url, {
        method: "GET",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "x-request-id": crypto.randomUUID(),
          Accept: "application/json",
        },
      });
    } catch {
      throw new EtoroError("unavailable", `GET ${path} failed`);
    }
    if (r.ok) {
      try {
        return await r.json();
      } catch {
        throw new EtoroError("bad_response", `GET ${path} non-JSON`, r.status);
      }
    }
    await r.body?.cancel();
    if (r.status === 401) throw new EtoroError("unauthorized", `GET ${path} 401`, 401);
    if (r.status === 403) throw new EtoroError("forbidden", `GET ${path} 403`, 403);
    if (r.status === 429) {
      const retry = Number(r.headers.get("retry-after"));
      throw new EtoroError("rate_limited", `GET ${path} 429`, 429, Number.isFinite(retry) ? retry : undefined);
    }
    if (r.status >= 500) throw new EtoroError("unavailable", `GET ${path} ${r.status}`, r.status);
    throw new EtoroError("bad_response", `GET ${path} ${r.status}`, r.status);
  }

  private async tokenRequest(body: URLSearchParams): Promise<Record<string, unknown>> {
    const { tokenEndpoint } = await this.endpoints();
    let r: Response;
    try {
      r = await this.timedFetch(tokenEndpoint, {
        method: "POST",
        headers: {
          // El host del SSO exige form-urlencoded (JSON da 400 sin cuerpo).
          "Content-Type": "application/x-www-form-urlencoded",
          Authorization: this.basicAuth(),
        },
        body: body.toString(),
      });
    } catch {
      throw new EtoroError("unavailable", "token endpoint unreachable");
    }
    let data: Record<string, unknown> = {};
    try {
      data = await r.json();
    } catch {
      // cuerpo vacío o no JSON
    }
    if (r.ok) return data;
    if (r.status === 400 && data.error === "invalid_grant") {
      throw new EtoroError("invalid_grant", "invalid_grant", 400);
    }
    if (r.status === 429) throw new EtoroError("rate_limited", "token endpoint 429", 429);
    if (r.status >= 500) throw new EtoroError("unavailable", `token endpoint ${r.status}`, r.status);
    // invalid_client, unauthorized_client…: problema de configuración nuestro.
    throw new EtoroError("config", `token endpoint ${r.status} ${String(data.error ?? "")}`, r.status);
  }

  private toTokens(data: Record<string, unknown>, previousRefresh: string | null): EtoroTokens {
    if (typeof data.access_token !== "string") throw new EtoroError("bad_response", "token response without access_token");
    const expiresIn = typeof data.expires_in === "number" ? data.expires_in : 3600;
    return {
      accessToken: data.access_token,
      refreshToken: typeof data.refresh_token === "string" ? data.refresh_token : previousRefresh,
      expiresAt: this.now() + expiresIn * 1000,
      scope: typeof data.scope === "string" ? data.scope.split(/\s+/).filter(Boolean) : [],
    };
  }

  private async jwks(force: boolean): Promise<JSONWebKeySet> {
    if (!force && jwksCache && this.now() - jwksCache.at < discoveryTtlMs) return jwksCache.jwks;
    const { jwksUri } = await this.endpoints();
    const r = await this.timedFetch(jwksUri, {});
    if (!r.ok) {
      await r.body?.cancel();
      throw new EtoroError("unavailable", "jwks unavailable", r.status);
    }
    const jwks = (await r.json()) as JSONWebKeySet;
    jwksCache = { at: this.now(), jwks };
    return jwks;
  }

  private basicAuth(): string {
    return "Basic " + btoa(`${this.credentials.clientId}:${this.credentials.clientSecret}`);
  }

  private timedFetch(url: string, init: RequestInit): Promise<Response> {
    return this.fetchImpl(url, { ...init, signal: AbortSignal.timeout(etoroConfig.requestTimeoutMs) });
  }
}

/// Scopes concedidos que permitirían operar. Porty no acepta ninguno.
export function writeScopes(scopes: string[]): string[] {
  return scopes.filter((s) => /:write\b/.test(s) || /\.write\b/.test(s));
}

// ── PKCE / state ───────────────────────────────────────────────────────────

function base64Url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function randomToken(bytes = 32): string {
  return base64Url(crypto.getRandomValues(new Uint8Array(bytes)));
}

export async function codeChallengeS256(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return base64Url(new Uint8Array(digest));
}

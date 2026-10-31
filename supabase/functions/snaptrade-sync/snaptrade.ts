// Cliente de la API de SnapTrade, solo lo que hace falta para leer: alta y
// baja del usuario, el Connection Portal (siempre de solo lectura), las
// conexiones, las cuentas y sus posiciones.
//
// Cada pedido lleva `clientId` y `timestamp` en el query y el header
// `Signature`: HMAC-SHA256 (base64), con la consumer key, del JSON con las
// claves ordenadas de {content, path, query}. Es lo mismo que hace el SDK
// oficial (`snaptrade-typescript-sdk` 13.1.14, `requestAfterHook`).
//
// Docs: https://docs.snaptrade.com/reference (rutas sin el prefijo /api/v1,
// que está deprecado).

export const snaptradeConfig = {
  defaultBaseUrl: "https://api.snaptrade.com",
};

export type SnaptradeCredentials = { clientId: string; consumerKey: string };

/// El usuario de SnapTrade de un usuario de Porty.
export type SnaptradeUser = { userId: string; userSecret: string };

/// Errores tipados.
/// - auth: 401, la firma o el secreto del usuario no valen.
/// - not_found: 404 (usuario o conexión que ya no existe).
/// - rate_limited: 429.
/// - unavailable: red, 5xx o una respuesta que no se entiende.
export type SnaptradeErrorType = "auth" | "not_found" | "rate_limited" | "unavailable";

export class SnaptradeError extends Error {
  constructor(readonly type: SnaptradeErrorType, readonly status = 0) {
    super(`snaptrade_${type}`);
  }
}

export type Authorization = {
  id: string;
  name: string;
  slug: string;
  /// `read` o `trade`. Porty solo crea `read`.
  type: string;
  disabled: boolean;
  createdAt: string;
  /// La web del bróker (para "Abrir en tu bróker"); null si no la informa.
  url: string | null;
};

export type Account = { id: string; authorizationId: string; name: string; institution: string };

/// Una posición de `/accounts/{id}/positions/all`. Los números vienen como
/// texto.
export type RawPosition = {
  kind: string;
  symbol: string;
  rawSymbol: string;
  description: string | null;
  units: number;
  price: number | null;
  costBasis: number | null;
  currency: string | null;
  cashEquivalent: boolean;
};

/// JSON con las claves ordenadas en todos los niveles (como
/// `JSONstringifyOrder` del SDK).
export function sortedJson(value: unknown): string {
  return JSON.stringify(value, (_key, v) => {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      return Object.fromEntries(Object.keys(v).sort().map((k) => [k, (v as Record<string, unknown>)[k]]));
    }
    return v;
  });
}

export async function signature(consumerKey: string, path: string, query: string, content: unknown): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(encodeURI(consumerKey)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const message = sortedJson({ content: content ?? null, path, query });
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
  let binary = "";
  for (const b of sig) binary += String.fromCharCode(b);
  return btoa(binary);
}

const num = (v: unknown): number | null => {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

export class SnaptradeClient {
  constructor(
    private readonly fetchFn: typeof fetch,
    private readonly now: () => number,
    private readonly credentials: SnaptradeCredentials,
    private readonly baseUrl = snaptradeConfig.defaultBaseUrl,
  ) {}

  async registerUser(userId: string): Promise<SnaptradeUser> {
    const body = await this.request("POST", "/snapTrade/registerUser", {}, { userId }) as Record<string, unknown>;
    if (typeof body?.userSecret !== "string") throw new SnaptradeError("unavailable");
    return { userId, userSecret: body.userSecret };
  }

  /// Borra el usuario y todo lo suyo en SnapTrade (deja de cobrarse). Si ya
  /// no existía, no es un error.
  async deleteUser(userId: string): Promise<void> {
    try {
      await this.request("DELETE", "/snapTrade/deleteUser", { userId });
    } catch (e) {
      if (!(e instanceof SnaptradeError && e.type === "not_found")) throw e;
    }
  }

  /// URL del Connection Portal (vence a los 5 minutos). Siempre de solo
  /// lectura. [reconnect]: el id de una conexión caída para reconectarla.
  async portalUrl(user: SnaptradeUser, opts: {
    redirect: string;
    darkMode: boolean;
    reconnect?: string;
  }): Promise<string> {
    const body = await this.request("POST", "/snapTrade/login", this.userQuery(user), {
      connectionType: "read",
      immediateRedirect: true,
      customRedirect: opts.redirect,
      darkMode: opts.darkMode,
      showCloseButton: true,
      ...(opts.reconnect ? { reconnect: opts.reconnect } : {}),
    }) as Record<string, unknown>;
    if (typeof body?.redirectURI !== "string") throw new SnaptradeError("unavailable");
    return body.redirectURI;
  }

  async authorizations(user: SnaptradeUser): Promise<Authorization[]> {
    const body = await this.request("GET", "/authorizations", this.userQuery(user));
    if (!Array.isArray(body)) throw new SnaptradeError("unavailable");
    return (body as Record<string, unknown>[]).flatMap((a) => {
      if (typeof a.id !== "string") return [];
      const brokerage = (a.brokerage ?? {}) as Record<string, unknown>;
      return [{
        id: a.id,
        name: String(brokerage.display_name ?? brokerage.name ?? a.name ?? ""),
        slug: String(brokerage.slug ?? ""),
        type: String(a.type ?? "read"),
        disabled: a.disabled === true,
        createdAt: String(a.created_date ?? ""),
        url: typeof brokerage.url === "string" && /^https:\/\//.test(brokerage.url) ? brokerage.url : null,
      }];
    });
  }

  async deleteAuthorization(user: SnaptradeUser, authorizationId: string): Promise<void> {
    try {
      await this.request("DELETE", `/authorizations/${encodeURIComponent(authorizationId)}`, this.userQuery(user));
    } catch (e) {
      if (!(e instanceof SnaptradeError && e.type === "not_found")) throw e;
    }
  }

  /// Pide a SnapTrade que actualice ya una conexión (asíncrono; se cobra
  /// aparte en el plan Daily).
  async refreshAuthorization(user: SnaptradeUser, authorizationId: string): Promise<void> {
    await this.request(
      "POST",
      `/authorizations/${encodeURIComponent(authorizationId)}/refresh`,
      this.userQuery(user),
    );
  }

  async accounts(user: SnaptradeUser): Promise<Account[]> {
    const body = await this.request("GET", "/accounts", this.userQuery(user));
    if (!Array.isArray(body)) throw new SnaptradeError("unavailable");
    return (body as Record<string, unknown>[]).flatMap((a) =>
      typeof a.id === "string" && typeof a.brokerage_authorization === "string"
        ? [{
          id: a.id,
          authorizationId: a.brokerage_authorization,
          name: String(a.name ?? ""),
          institution: String(a.institution_name ?? ""),
        }]
        : []
    );
  }

  async positions(user: SnaptradeUser, accountId: string): Promise<RawPosition[]> {
    const body = await this.request(
      "GET",
      `/accounts/${encodeURIComponent(accountId)}/positions/all`,
      this.userQuery(user),
    ) as Record<string, unknown>;
    const results = body?.results;
    if (!Array.isArray(results)) throw new SnaptradeError("unavailable");
    return (results as Record<string, unknown>[]).flatMap((p) => {
      const instrument = (p.instrument ?? {}) as Record<string, unknown>;
      const units = num(p.units);
      if (units === null) return [];
      return [{
        kind: String(instrument.kind ?? "other"),
        symbol: String(instrument.symbol ?? ""),
        rawSymbol: String(instrument.raw_symbol ?? instrument.symbol ?? ""),
        description: typeof instrument.description === "string" ? instrument.description : null,
        units,
        price: num(p.price),
        costBasis: num(p.cost_basis),
        currency: typeof p.currency === "string" ? p.currency : null,
        cashEquivalent: p.cash_equivalent === true,
      }];
    });
  }

  private userQuery(user: SnaptradeUser): Record<string, string> {
    return { userId: user.userId, userSecret: user.userSecret };
  }

  private async request(
    method: string,
    path: string,
    params: Record<string, string> = {},
    content?: Record<string, unknown>,
  ): Promise<unknown> {
    const query = new URLSearchParams({
      clientId: this.credentials.clientId,
      ...params,
      timestamp: String(Math.round(this.now() / 1000)),
    }).toString();
    const sig = await signature(this.credentials.consumerKey, path, query, content ?? null);
    let res: Response;
    try {
      res = await this.fetchFn(`${this.baseUrl}${path}?${query}`, {
        method,
        headers: {
          Signature: sig,
          Accept: "application/json",
          ...(content ? { "Content-Type": "application/json" } : {}),
        },
        ...(content ? { body: JSON.stringify(content) } : {}),
      });
    } catch {
      throw new SnaptradeError("unavailable");
    }
    if (res.ok) {
      const text = await res.text();
      if (!text) return null;
      try {
        return JSON.parse(text);
      } catch {
        throw new SnaptradeError("unavailable", res.status);
      }
    }
    await res.body?.cancel();
    if (res.status === 401 || res.status === 403) throw new SnaptradeError("auth", res.status);
    if (res.status === 404) throw new SnaptradeError("not_found", 404);
    if (res.status === 429) throw new SnaptradeError("rate_limited", 429);
    throw new SnaptradeError("unavailable", res.status);
  }
}

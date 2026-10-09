// eToro falso (SSO + Public API) para los tests de etoro-sync: responde por
// `fetch` sin red. Firma ID tokens RS256 de verdad con una clave generada en
// el momento, así la validación (firma, iss, aud, nonce) corre completa.

import { exportJWK, generateKeyPair, SignJWT } from "npm:jose@5";

const { publicKey, privateKey } = await generateKeyPair("RS256");
const jwk = { ...(await exportJWK(publicKey)), kid: "k1", alg: "RS256", use: "sig" };

export type Call = { url: string; method: string; body: string | null; headers: Headers };

export class FakeEtoro {
  calls: Call[] = [];
  /// nonce → se firma en el próximo id_token.
  nonce = "";
  sub = "pairwise-sub-1";
  grantedScope = "openid etoro-public:real:read";
  accessCounter = 0;
  refreshCounter = 0;
  validAccess = new Set<string>();
  validRefresh = new Set<string>();
  refreshInvalid = false;
  apiStatus: number | null = null;
  apiStatusOnce = false;
  positions: Record<string, unknown>[] = [
    { positionID: 11, instrumentID: 1001, mirrorID: 0, settlementTypeID: 1, isBuy: true, leverage: 1, units: 10, openRate: 180, amount: 1800, openDateTime: "2025-03-10T14:31:00Z" },
    { positionID: 12, instrumentID: 1001, mirrorID: 0, settlementTypeID: 1, isBuy: true, leverage: 1, units: 5, openRate: 210, amount: 1050, openDateTime: "2026-01-05T15:00:00Z" },
    { positionID: 13, instrumentID: 1002, mirrorID: 0, settlementTypeID: 1, isBuy: true, leverage: 1, units: 0.5, openRate: 500, amount: 250, openDateTime: "2026-02-01T15:00:00Z" },
    { positionID: 14, instrumentID: 1001, mirrorID: 0, settlementTypeID: 0, isBuy: true, leverage: 5, units: 3, openRate: 200, amount: 120, openDateTime: "2026-02-01T15:00:00Z" },
    { positionID: 15, instrumentID: 1001, mirrorID: 99, settlementTypeID: 1, isBuy: true, leverage: 1, units: 1, openRate: 200, amount: 200, openDateTime: "2026-02-01T15:00:00Z" },
  ];
  history: Record<string, unknown>[] = [
    { positionId: 900, instrumentId: 1002, isBuy: true, leverage: 1, openRate: 300, closeRate: 320, units: 2, netProfit: 38.5, fees: 1.5, parentPositionId: 0, closeTimestamp: "2026-06-24T15:00:00Z" },
  ];

  issue(withRefresh = true) {
    const access = `at-${++this.accessCounter}`;
    this.validAccess.add(access);
    const out: Record<string, unknown> = { token_type: "Bearer", expires_in: 3600, access_token: access, scope: this.grantedScope };
    if (withRefresh) {
      const refresh = `rt-${++this.refreshCounter}`;
      this.validRefresh.add(refresh);
      out.refresh_token = refresh;
    }
    return out;
  }

  fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    const method = init?.method ?? "GET";
    const body = typeof init?.body === "string" ? init.body : null;
    this.calls.push({ url, method, body, headers: new Headers(init?.headers) });
    const u = new URL(url);

    if (url === "https://www.etoro.com/.well-known/openid-configuration") {
      return Response.json({
        issuer: "https://www.etoro.com",
        authorization_endpoint: "https://www.etoro.com/sso",
        token_endpoint: "https://www.etoro.com/api/sso/v1/token",
        revocation_endpoint: "https://www.etoro.com/api/sso/v1/token/revoke",
        jwks_uri: "https://www.etoro.com/.well-known/jwks.json",
      });
    }
    if (url === "https://www.etoro.com/.well-known/jwks.json") return Response.json({ keys: [jwk] });
    if (url === "https://www.etoro.com/api/sso/v1/token/revoke") {
      const token = new URLSearchParams(body ?? "").get("token")!;
      this.validAccess.delete(token);
      this.validRefresh.delete(token);
      return new Response(null, { status: 200 });
    }
    if (url === "https://www.etoro.com/api/sso/v1/token") {
      const form = new URLSearchParams(body ?? "");
      if (init?.headers && new Headers(init.headers).get("authorization") !== "Basic " + btoa("porty-client:porty-secret")) {
        return Response.json({ error: "invalid_client" }, { status: 401 });
      }
      if (form.get("grant_type") === "authorization_code") {
        if (form.get("code") !== "good-code" || !form.get("code_verifier")) {
          return Response.json({ error: "invalid_grant" }, { status: 400 });
        }
        const idToken = await new SignJWT({ nonce: this.nonce })
          .setProtectedHeader({ alg: "RS256", kid: "k1" })
          .setIssuer("https://www.etoro.com")
          .setAudience("porty-client")
          .setSubject(this.sub)
          .setIssuedAt()
          .setExpirationTime("5m")
          .sign(privateKey);
        return Response.json({ ...this.issue(), id_token: idToken });
      }
      if (form.get("grant_type") === "refresh_token") {
        const rt = form.get("refresh_token")!;
        if (this.refreshInvalid || !this.validRefresh.has(rt)) return Response.json({ error: "invalid_grant" }, { status: 400 });
        this.validRefresh.delete(rt); // rotación
        return Response.json(this.issue());
      }
    }

    if (u.host === "public-api.etoro.com") {
      if (method !== "GET") return new Response("only GET in this fake", { status: 418 });
      const token = new Headers(init?.headers).get("authorization")?.replace("Bearer ", "") ?? "";
      if (this.apiStatus) {
        const status = this.apiStatus;
        if (this.apiStatusOnce) this.apiStatus = null;
        return new Response("{}", { status, headers: status === 429 ? { "retry-after": "30" } : {} });
      }
      if (!this.validAccess.has(token)) return new Response("{}", { status: 401 });
      switch (u.pathname) {
        case "/api/v1/trading/info/real/pnl":
        case "/api/v1/trading/info/demo/pnl":
          return Response.json({ clientPortfolio: { credit: 100, positions: this.positions, mirrors: [] } });
        case "/api/v1/trading/info/trade/history":
        case "/api/v1/trading/info/trade/demo/history":
          return Response.json(this.history);
        case "/api/v1/market-data/instruments": {
          const ids = (u.searchParams.get("instrumentIds") ?? "").split(",").map(Number);
          const all = [
            { instrumentID: 1001, symbolFull: "AAPL", instrumentDisplayName: "Apple", instrumentTypeID: 5, exchangeID: 4 },
            { instrumentID: 1002, symbolFull: "VOO", instrumentDisplayName: "Vanguard S&P 500", instrumentTypeID: 6, exchangeID: 5 },
          ];
          return Response.json({ instrumentDisplayDatas: all.filter((i) => ids.includes(i.instrumentID)) });
        }
        case "/api/v1/market-data/instrument-types":
          return Response.json({ instrumentTypes: [{ instrumentTypeID: 5, instrumentTypeDescription: "Stocks" }, { instrumentTypeID: 6, instrumentTypeDescription: "ETF" }] });
        case "/api/v1/market-data/exchanges":
          return Response.json({ exchangeInfo: [{ exchangeID: 4, exchangeDescription: "Nasdaq" }, { exchangeID: 5, exchangeDescription: "NYSE" }] });
      }
    }
    return new Response("unexpected " + url, { status: 404 });
  };

  apiCalls() {
    return this.calls.filter((c) => c.url.startsWith("https://public-api.etoro.com"));
  }
}


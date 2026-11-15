// Sign in with Apple: revocar el acceso de Porty a la cuenta de Apple al
// borrar la cuenta (App Store Review Guideline 5.1.1(v)).
//
// La app no guarda tokens de Apple: al borrar, pide a Apple un código de un
// uso (authorization code, vence a los 5 minutos) y lo manda acá. Se canjea
// por un refresh token en /auth/token y ese token se revoca en /auth/revoke.
// Las dos llamadas se autentican con un client secret: un JWT ES256 firmado
// con la key de Sign in with Apple (.p8).
//
// Secrets: APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_CLIENT_ID (el bundle id, porque
// el login es nativo) y APPLE_PRIVATE_KEY (el contenido del .p8).

export const appleConfig = {
  tokenUrl: "https://appleid.apple.com/auth/token",
  revokeUrl: "https://appleid.apple.com/auth/revoke",
  audience: "https://appleid.apple.com",
  /// El client secret dura lo justo para estas dos llamadas.
  secretTtlSeconds: 300,
  maxCodeLength: 2048,
};

export type AppleCredentials = {
  teamId: string;
  keyId: string;
  clientId: string;
  privateKey: string;
};

export type AppleRevokeOutcome = "revoked" | "exchange_failed" | "revoke_failed" | "misconfigured";

export function appleCredentials(env: (name: string) => string | undefined): AppleCredentials | null {
  const teamId = env("APPLE_TEAM_ID")?.trim();
  const keyId = env("APPLE_KEY_ID")?.trim();
  const clientId = env("APPLE_CLIENT_ID")?.trim();
  const privateKey = env("APPLE_PRIVATE_KEY");
  if (!teamId || !keyId || !clientId || !privateKey) return null;
  return { teamId, keyId, clientId, privateKey };
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const encodeJson = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));

/// El .p8 es PKCS#8 en PEM. Acepta saltos de línea reales o escritos como
/// `\n` (lo que queda si el secreto se cargó desde un .env de una línea).
function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/[^A-Za-z0-9+/=]/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/// JWT ES256 que Apple acepta como client_secret. WebCrypto devuelve la firma
/// ECDSA como r||s (64 bytes), que es el formato que pide JWS.
export async function appleClientSecret(creds: AppleCredentials, nowMs: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(creds.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const iat = Math.floor(nowMs / 1000);
  const header = encodeJson({ alg: "ES256", kid: creds.keyId, typ: "JWT" });
  const payload = encodeJson({
    iss: creds.teamId,
    iat,
    exp: iat + appleConfig.secretTtlSeconds,
    aud: appleConfig.audience,
    sub: creds.clientId,
  });
  const signingInput = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

function form(fields: Record<string, string>): RequestInit {
  return {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body: new URLSearchParams(fields).toString(),
  };
}

/// Canjea el código y revoca. Nunca tira: el borrado de la cuenta no depende
/// de que Apple responda (best effort, como la revocación de eToro).
export async function revokeAppleAccess(
  fetchFn: typeof fetch,
  creds: AppleCredentials | null,
  authorizationCode: string,
  nowMs: number,
): Promise<AppleRevokeOutcome> {
  if (!creds) return "misconfigured";
  let clientSecret: string;
  try {
    clientSecret = await appleClientSecret(creds, nowMs);
  } catch {
    return "misconfigured";
  }

  let token: string | null = null;
  let tokenType = "refresh_token";
  try {
    const response = await fetchFn(appleConfig.tokenUrl, form({
      client_id: creds.clientId,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }));
    if (!response.ok) {
      await response.body?.cancel();
      return "exchange_failed";
    }
    const data = await response.json() as { refresh_token?: unknown; access_token?: unknown };
    if (typeof data.refresh_token === "string" && data.refresh_token) {
      token = data.refresh_token;
    } else if (typeof data.access_token === "string" && data.access_token) {
      token = data.access_token;
      tokenType = "access_token";
    }
  } catch {
    return "exchange_failed";
  }
  if (!token) return "exchange_failed";

  try {
    const response = await fetchFn(appleConfig.revokeUrl, form({
      client_id: creds.clientId,
      client_secret: clientSecret,
      token,
      token_type_hint: tokenType,
    }));
    await response.body?.cancel();
    return response.ok ? "revoked" : "revoke_failed";
  } catch {
    return "revoke_failed";
  }
}

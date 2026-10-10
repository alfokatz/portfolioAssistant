// Cliente mínimo de FCM HTTP v1: token OAuth con la service account
// (JWT RS256 firmado con WebCrypto, sin dependencias) y envío a un token.
//
// Secret: FCM_SERVICE_ACCOUNT = el JSON de la service account de Firebase
// (rol "Firebase Cloud Messaging API Admin").

export type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

export type FcmMessage = {
  token: string;
  title: string;
  body: string;
  data: Record<string, string>;
  androidChannel: string;
  interruption: "time-sensitive" | "active";
  threadId: string;
};

/// ok · invalid_token (borrar el dispositivo) · retry (red, 429, 5xx) ·
/// error (otro 4xx: no se reintenta).
export type SendResult = "ok" | "invalid_token" | "retry" | "error";

export interface PushSender {
  send(message: FcmMessage): Promise<SendResult>;
}

const scope = "https://www.googleapis.com/auth/firebase.messaging";

function base64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let s = "";
  for (const b of raw) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importKey(pem: string): Promise<CryptoKey> {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

export async function signJwt(account: ServiceAccount, nowMs: number): Promise<string> {
  const iat = Math.floor(nowMs / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: account.client_email,
    scope,
    aud: account.token_uri ?? "https://oauth2.googleapis.com/token",
    iat,
    exp: iat + 3600,
  }));
  const key = await importKey(account.private_key);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${base64url(new Uint8Array(sig))}`;
}

export class FcmSender implements PushSender {
  #token: { value: string; expiresAt: number } | null = null;

  constructor(
    private readonly account: ServiceAccount,
    private readonly fetchImpl: typeof fetch,
    private readonly now: () => number,
  ) {}

  static fromEnv(json: string | undefined, fetchImpl: typeof fetch, now: () => number): FcmSender | null {
    if (!json) return null;
    try {
      const account = JSON.parse(json) as ServiceAccount;
      if (!account.project_id || !account.client_email || !account.private_key) return null;
      return new FcmSender(account, fetchImpl, now);
    } catch {
      return null;
    }
  }

  async accessToken(force = false): Promise<string | null> {
    if (!force && this.#token && this.#token.expiresAt > this.now() + 60_000) return this.#token.value;
    const assertion = await signJwt(this.account, this.now());
    let res: Response;
    try {
      res = await this.fetchImpl(this.account.token_uri ?? "https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
          assertion,
        }).toString(),
      });
    } catch {
      return null;
    }
    if (res.status !== 200) {
      await res.body?.cancel();
      return null;
    }
    const body = await res.json() as { access_token?: string; expires_in?: number };
    if (!body.access_token) return null;
    this.#token = { value: body.access_token, expiresAt: this.now() + (body.expires_in ?? 3600) * 1000 };
    return body.access_token;
  }

  async send(m: FcmMessage): Promise<SendResult> {
    for (let attempt = 0; attempt < 2; attempt++) {
      const token = await this.accessToken(attempt > 0);
      if (!token) return "retry";
      let res: Response;
      try {
        res = await this.fetchImpl(
          `https://fcm.googleapis.com/v1/projects/${this.account.project_id}/messages:send`,
          {
            method: "POST",
            headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
            body: JSON.stringify({ message: toFcm(m) }),
          },
        );
      } catch {
        return "retry";
      }
      if (res.status === 200) {
        await res.body?.cancel();
        return "ok";
      }
      // Token OAuth vencido o revocado: uno nuevo y otra vez.
      if (res.status === 401 && attempt === 0) {
        await res.body?.cancel();
        continue;
      }
      const text = await res.text();
      return classify(res.status, text);
    }
    return "retry";
  }
}

/// El mensaje tal como lo espera FCM v1.
export function toFcm(m: FcmMessage) {
  return {
    token: m.token,
    notification: { title: m.title, body: m.body },
    data: m.data,
    android: {
      priority: "high",
      notification: { channel_id: m.androidChannel, tag: m.threadId },
    },
    apns: {
      headers: { "apns-priority": "10", "apns-push-type": "alert" },
      payload: {
        aps: {
          sound: "default",
          "thread-id": m.threadId,
          "interruption-level": m.interruption,
        },
      },
    },
  };
}

/// Errores de FCM v1: https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode
export function classify(status: number, text: string): SendResult {
  let code = "";
  try {
    const body = JSON.parse(text);
    const details = body?.error?.details ?? [];
    code = details.find((d: { errorCode?: string }) => d.errorCode)?.errorCode ?? body?.error?.status ?? "";
  } catch {
    // sin cuerpo JSON
  }
  if (code === "UNREGISTERED" || status === 404) return "invalid_token";
  if (code === "INVALID_ARGUMENT" && /token/i.test(text)) return "invalid_token";
  if (code === "SENDER_ID_MISMATCH") return "invalid_token";
  if (status === 429 || status >= 500 || code === "UNAVAILABLE" || code === "INTERNAL" || code === "QUOTA_EXCEEDED") {
    return "retry";
  }
  return "error";
}

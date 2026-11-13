// Revocación de Sign in with Apple al borrar la cuenta (delete-account/apple.ts):
// client secret ES256 verificable, canje del código, revoke y best effort.
//   deno test --allow-net --allow-env --allow-read tests/delete_account_apple_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import { appleClientSecret, appleCredentials, revokeAppleAccess } from "../delete-account/apple.ts";
import { handle } from "../delete-account/handler.ts";

const NOW = Date.parse("2026-11-13T12:00:00Z");

async function testKey() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let b64 = btoa(String.fromCharCode(...der));
  b64 = b64.match(/.{1,64}/g)!.join("\n");
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----`;
  return { pem, publicKey: pair.publicKey };
}

function fromB64url(s: string): Uint8Array<ArrayBuffer> {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (s.length % 4)) % 4);
  const binary = atob(b64);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

type Call = { url: string; body: URLSearchParams };

function fakeApple(opts: { token?: number; revoke?: number; tokenBody?: unknown; down?: boolean } = {}) {
  const calls: Call[] = [];
  const fetchFn = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, body: new URLSearchParams(String(init?.body ?? "")) });
    if (opts.down) throw new TypeError("network");
    if (url.endsWith("/auth/token")) {
      return new Response(JSON.stringify(opts.tokenBody ?? { refresh_token: "r-tok", access_token: "a-tok" }), {
        status: opts.token ?? 200,
      });
    }
    if (url.endsWith("/auth/revoke")) return new Response("", { status: opts.revoke ?? 200 });
    return new Response("unexpected", { status: 599 });
  }) as typeof fetch;
  return { fetchFn, calls };
}

Deno.test("client secret: ES256 con kid, iss, sub y aud de Apple, y firma válida", async () => {
  const { pem, publicKey } = await testKey();
  const jwt = await appleClientSecret({ teamId: "TEAM", keyId: "KEY", clientId: "com.portyassistant.app", privateKey: pem }, NOW);
  const [h, p, sig] = jwt.split(".");
  const header = JSON.parse(new TextDecoder().decode(fromB64url(h)));
  const payload = JSON.parse(new TextDecoder().decode(fromB64url(p)));
  assertEquals(header, { alg: "ES256", kid: "KEY", typ: "JWT" });
  assertEquals(payload.iss, "TEAM");
  assertEquals(payload.sub, "com.portyassistant.app");
  assertEquals(payload.aud, "https://appleid.apple.com");
  assertEquals(payload.iat, NOW / 1000);
  assertEquals(payload.exp - payload.iat, 300);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    fromB64url(sig),
    new TextEncoder().encode(`${h}.${p}`),
  );
  assert(ok, "la firma tiene que verificar con la clave pública");
});

Deno.test("acepta el .p8 con saltos de línea escritos como \\n", async () => {
  const { pem } = await testKey();
  const oneLine = pem.replace(/\n/g, "\\n");
  const jwt = await appleClientSecret({ teamId: "T", keyId: "K", clientId: "c", privateKey: oneLine }, NOW);
  assertEquals(jwt.split(".").length, 3);
});

Deno.test("canjea el código y revoca el refresh token", async () => {
  const { pem } = await testKey();
  const apple = fakeApple();
  const creds = { teamId: "T", keyId: "K", clientId: "com.portyassistant.app", privateKey: pem };
  assertEquals(await revokeAppleAccess(apple.fetchFn, creds, "code-1", NOW), "revoked");
  assertEquals(apple.calls.map((c) => new URL(c.url).pathname), ["/auth/token", "/auth/revoke"]);
  const [token, revoke] = apple.calls;
  assertEquals(token.body.get("grant_type"), "authorization_code");
  assertEquals(token.body.get("code"), "code-1");
  assertEquals(token.body.get("client_id"), "com.portyassistant.app");
  assert((token.body.get("client_secret") ?? "").split(".").length === 3);
  assertEquals(revoke.body.get("token"), "r-tok");
  assertEquals(revoke.body.get("token_type_hint"), "refresh_token");
});

Deno.test("sin refresh token revoca el access token", async () => {
  const { pem } = await testKey();
  const apple = fakeApple({ tokenBody: { access_token: "a-tok" } });
  const creds = { teamId: "T", keyId: "K", clientId: "c", privateKey: pem };
  assertEquals(await revokeAppleAccess(apple.fetchFn, creds, "code", NOW), "revoked");
  assertEquals(apple.calls[1].body.get("token"), "a-tok");
  assertEquals(apple.calls[1].body.get("token_type_hint"), "access_token");
});

Deno.test("fallas de Apple o de configuración no tiran", async () => {
  const { pem } = await testKey();
  const creds = { teamId: "T", keyId: "K", clientId: "c", privateKey: pem };
  assertEquals(await revokeAppleAccess(fakeApple({ token: 400 }).fetchFn, creds, "x", NOW), "exchange_failed");
  assertEquals(await revokeAppleAccess(fakeApple({ revoke: 500 }).fetchFn, creds, "x", NOW), "revoke_failed");
  assertEquals(await revokeAppleAccess(fakeApple({ down: true }).fetchFn, creds, "x", NOW), "exchange_failed");
  assertEquals(await revokeAppleAccess(fakeApple().fetchFn, null, "x", NOW), "misconfigured");
  const broken = { ...creds, privateKey: "no es una clave" };
  assertEquals(await revokeAppleAccess(fakeApple().fetchFn, broken, "x", NOW), "misconfigured");
  assertEquals(appleCredentials(() => undefined), null);
});

// ---------------------------------------------------------------------------
// En el handler
// ---------------------------------------------------------------------------

const UID = "11111111-2222-4333-8444-555555555555";

function fakeDb() {
  const ops: string[] = [];
  const db = {
    rpc: (name: string) => {
      ops.push(`rpc:${name}`);
      if (name === "rate_limit_hit") return Promise.resolve({ data: true, error: null });
      return Promise.resolve({ data: null, error: null });
    },
    auth: {
      admin: {
        deleteUser: () => {
          ops.push("auth:deleteUser");
          return Promise.resolve({ data: {}, error: null });
        },
      },
    },
  };
  return { db, ops };
}

async function run(body: Record<string, unknown>, apple: ReturnType<typeof fakeApple>, env: Record<string, string>) {
  const fake = fakeDb();
  const fetchFn = (async (input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input).includes("appleid.apple.com")) return apple.fetchFn(input, init);
    return new Response("{}", { status: 200 }); // RevenueCat
  }) as typeof fetch;
  const r = await handle(
    new Request("http://local/delete-account", {
      method: "POST",
      headers: { Authorization: "Bearer jwt", "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }),
    {
      // deno-lint-ignore no-explicit-any
      db: fake.db as any,
      authenticate: () => Promise.resolve(UID),
      fetch: fetchFn,
      env: (k: string) => env[k],
      now: () => NOW,
      background: () => {},
    },
  );
  return { r, ops: fake.ops };
}

Deno.test("handler: con apple_authorization_code revoca en Apple antes de borrar el usuario", async () => {
  const { pem } = await testKey();
  const apple = fakeApple();
  const env = {
    REVENUECAT_SECRET_API_KEY: "sk",
    APPLE_TEAM_ID: "T",
    APPLE_KEY_ID: "K",
    APPLE_CLIENT_ID: "com.portyassistant.app",
    APPLE_PRIVATE_KEY: pem,
  };
  const { r, ops } = await run({ confirm: true, apple_authorization_code: "code-9" }, apple, env);
  assertEquals(r.status, 200);
  assertEquals(apple.calls.map((c) => new URL(c.url).pathname), ["/auth/token", "/auth/revoke"]);
  assertEquals(ops.at(-1), "auth:deleteUser");
});

Deno.test("handler: Apple caído o sin configurar no frena el borrado", async () => {
  const { pem } = await testKey();
  const env = {
    REVENUECAT_SECRET_API_KEY: "sk",
    APPLE_TEAM_ID: "T",
    APPLE_KEY_ID: "K",
    APPLE_CLIENT_ID: "c",
    APPLE_PRIVATE_KEY: pem,
  };
  const down = await run({ confirm: true, apple_authorization_code: "x" }, fakeApple({ down: true }), env);
  assertEquals(down.r.status, 200);
  assert(down.ops.includes("auth:deleteUser"));

  const unconfigured = fakeApple();
  const noKeys = await run({ confirm: true, apple_authorization_code: "x" }, unconfigured, { REVENUECAT_SECRET_API_KEY: "sk" });
  assertEquals(noKeys.r.status, 200);
  assertEquals(unconfigured.calls.length, 0);
});

Deno.test("handler: sin código no llama a Apple", async () => {
  const apple = fakeApple();
  const { r } = await run({ confirm: true }, apple, { REVENUECAT_SECRET_API_KEY: "sk" });
  assertEquals(r.status, 200);
  assertEquals(apple.calls.length, 0);
});

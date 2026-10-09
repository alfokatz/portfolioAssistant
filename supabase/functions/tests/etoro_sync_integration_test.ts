// etoro-sync contra el stack LOCAL de Supabase (Postgres + PostgREST + Auth
// con todas las migraciones, Vault incluido) y eToro falso. Es la prueba de
// punta a punta del servidor: store real, RPCs reales, RLS y trigger reales.
//
// Requiere `supabase start` (ver README_TESTS.md / deno task test).

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { resetEtoroCaches } from "../etoro-sync/etoro.ts";
import { handle } from "../etoro-sync/handler.ts";
import { FakeEtoro } from "./etoro_fakes.ts";
import { createUser, db, deps } from "./helpers.ts";

const env = {
  ETORO_CLIENT_ID: "porty-client",
  ETORO_CLIENT_SECRET: "porty-secret",
  ETORO_REDIRECT_URI: "http://127.0.0.1:54321/functions/v1/etoro-sync/callback",
};

const url = Deno.env.get("API_URL") ?? Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const anonKey = Deno.env.get("ANON_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

/// Cliente "de la app": rol authenticated con el JWT del usuario.
function asUser(jwt: string) {
  return createClient(url, anonKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
}

function post(path: string, jwt: string, body?: unknown): Request {
  return new Request(`http://local/functions/v1/etoro-sync${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

async function connect(fake: FakeEtoro, d: ReturnType<typeof deps>, jwt: string) {
  const start = await handle(post("/connect/start", jwt), d);
  assertEquals(start.status, 200);
  const authorizeUrl = new URL((await start.json()).authorizeUrl);
  fake.nonce = authorizeUrl.searchParams.get("nonce")!;
  return await handle(
    new Request(
      `http://local/functions/v1/etoro-sync/callback?code=good-code&state=${authorizeUrl.searchParams.get("state")}`,
    ),
    d,
  );
}

Deno.test("punta a punta: conectar, importar, convivir con lo manual, token vencido, desconectar", async () => {
  resetEtoroCaches();
  const user = await createUser("premium");
  const app = asUser(user.jwt);
  const fake = new FakeEtoro();
  let now = Date.now();
  const d = deps(fake.fetch as typeof fetch, env, () => now);

  // Una posición cargada a mano antes de conectar (mismo ticker que eToro).
  const manualId = crypto.randomUUID();
  const ins = await app.from("positions").insert({
    id: manualId,
    user_id: user.id,
    ticker: "AAPL",
    quantity: 3,
    purchase_price: 150,
    purchase_date: "2025-01-01T00:00:00Z",
  });
  assertEquals(ins.error, null);

  // ── conectar ──────────────────────────────────────────────────────────────
  const cb = await connect(fake, d, user.jwt);
  assertEquals(cb.headers.get("location"), "porty-etoro://callback?status=ok");

  // La app ve su conexión (RLS) con el resultado, y nada de tokens.
  const conn = await app.from("etoro_connections").select("*").single();
  assertEquals(conn.data!.status, "connected");
  assertEquals(conn.data!.last_result.imported, 3);
  assertEquals(conn.data!.last_result.possibleDuplicates, ["AAPL"]);
  assertFalse(JSON.stringify(conn.data).includes("at-"));
  const tokensAsUser = await app.from("etoro_tokens").select("*");
  assertEquals(tokensAsUser.data ?? [], []);
  const vaultAsUser = await app.rpc("etoro_tokens_read", { p_user_id: user.id });
  assert(vaultAsUser.error, "la app no puede leer tokens");

  // Los tokens están en Vault (solo la service role los lee).
  const secret = await db.rpc("etoro_tokens_read", { p_user_id: user.id });
  assert(JSON.parse(secret.data).accessToken.startsWith("at-"));

  // Posiciones: la manual intacta + 3 de eToro; cerrada con P&L del bróker.
  const rows = (await app.from("positions").select("ticker, quantity, source, external_id").order("external_id")).data!;
  assertEquals(rows.filter((r) => r.source === "manual").length, 1);
  assertEquals(
    rows.filter((r) => r.source === "etoro").map((r) => [r.ticker, Number(r.quantity)]),
    [["AAPL", 10], ["AAPL", 5], ["VOO", 0.5]],
  );
  const closed = (await app.from("closed_positions").select("ticker, realized_pnl, source")).data!;
  assertEquals(closed.map((c) => [c.ticker, Number(c.realized_pnl), c.source]), [["VOO", 38.5, "etoro"]]);

  // ── solo lectura ──────────────────────────────────────────────────────────
  const edit = await app.from("positions").update({ quantity: 1 }).eq("source", "etoro");
  assert(edit.error, "editar una posición de eToro desde la app debe fallar");
  const delAll = await app.from("positions").delete().eq("ticker", "AAPL").eq("source", "manual");
  assertEquals(delAll.error, null); // "borrar las manuales" (duplicados) sí
  const left = (await app.from("positions").select("source")).data!;
  assertEquals(left.every((r) => r.source === "etoro"), true);

  // ── resincronizar: se cerró una en eToro ──────────────────────────────────
  fake.positions = fake.positions.filter((p) => p.positionID !== 12);
  now += 6 * 60 * 1000;
  const sync = await handle(post("/sync", user.jwt), d);
  assertEquals(sync.status, 200);
  const afterSync = (await app.from("positions").select("external_id").eq("source", "etoro")).data!;
  assertEquals(afterSync.map((r) => r.external_id).sort(), ["11", "13"]);

  // ── token vencido y revocado desde eToro ──────────────────────────────────
  fake.refreshInvalid = true;
  now += 2 * 60 * 60 * 1000;
  const dead = await handle(post("/sync", user.jwt), d);
  assertEquals(dead.status, 409);
  assertEquals((await dead.json()).error.type, "etoro_reconnect_required");
  const conn2 = await app.from("etoro_connections").select("status").single();
  assertEquals(conn2.data!.status, "reconnect_required");
  // Lo importado sigue en pantalla.
  assertEquals((await app.from("positions").select("id").eq("source", "etoro")).data!.length, 2);

  // ── desconectar conservando como manuales ─────────────────────────────────
  const disc = await handle(post("/disconnect", user.jwt, { keepAsManual: true }), d);
  assertEquals(disc.status, 200);
  const finalRows = (await app.from("positions").select("source, quantity")).data!;
  assertEquals(finalRows.length, 2);
  assert(finalRows.every((r) => r.source === "manual"));
  // Ya manuales, la app las edita.
  const editNow = await app.from("positions").update({ quantity: 1 }).eq("user_id", user.id);
  assertEquals(editNow.error, null);
  const secretAfter = await db.rpc("etoro_tokens_read", { p_user_id: user.id });
  assertEquals(secretAfter.data, null);
  const conn3 = await app.from("etoro_connections").select("status").single();
  assertEquals(conn3.data!.status, "disconnected");
});

Deno.test("plan Free no puede conectar (lo valida el servidor)", async () => {
  resetEtoroCaches();
  const user = await createUser("free");
  const r = await handle(post("/connect/start", user.jwt), deps(new FakeEtoro().fetch as typeof fetch, env));
  assertEquals(r.status, 403);
  assertEquals((await r.json()).error.type, "etoro_plan_required");
});

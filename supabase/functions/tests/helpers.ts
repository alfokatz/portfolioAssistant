// Helpers de los tests de las edge functions: Postgres REAL (supabase start,
// con todas las migraciones), y solo lo externo (OpenAI, Finnhub,
// RevenueCat) reemplazado por un `fetch` falso.
//
// Requiere: `supabase start` y las variables del stack local, que el task
// `deno task test` toma de `supabase status -o env` (ver README_TESTS.md).

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { Deps } from "../_shared/common.ts";

const url = Deno.env.get("API_URL") ?? Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const serviceKey = Deno.env.get("SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const anonKey = Deno.env.get("ANON_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

export const db: SupabaseClient = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

export type FakeFetch = {
  fetch: typeof fetch;
  calls: { url: string; init?: RequestInit; body?: unknown }[];
};

/// `fetch` falso que responde con [respond] y guarda cada llamada.
export function fakeFetch(
  respond: (url: string, init?: RequestInit, n?: number) => Response | Promise<Response>,
): FakeFetch {
  const calls: FakeFetch["calls"] = [];
  const fn = async (input: string | URL | Request, init?: RequestInit) => {
    const u = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    let body: unknown = undefined;
    if (typeof init?.body === "string") {
      try {
        body = JSON.parse(init.body);
      } catch {
        body = init.body;
      }
    }
    calls.push({ url: u, init, body });
    return await respond(u, init, calls.length);
  };
  return { fetch: fn as typeof fetch, calls };
}

export function deps(
  fetchImpl: typeof fetch,
  env: Record<string, string> = {},
  now: () => number = () => Date.now(),
): Deps & { settle: () => Promise<void> } {
  const pending: Promise<unknown>[] = [];
  return {
    db,
    authenticate: async (jwt: string) => {
      const { data, error } = await db.auth.getUser(jwt);
      return error || !data.user ? null : data.user.id;
    },
    fetch: fetchImpl,
    env: (name) => env[name],
    now,
    background: (task) => pending.push(task),
    settle: async () => {
      await Promise.all(pending);
    },
  };
}

/// Crea un usuario real en auth.users con su plan, y devuelve id + JWT.
export async function createUser(
  tier: "free" | "premium" | "gold" = "premium",
): Promise<{ id: string; jwt: string }> {
  const email = `t-${crypto.randomUUID()}@test.local`;
  const password = `P-${crypto.randomUUID()}`;
  const created = await db.auth.admin.createUser({ email, password, email_confirm: true });
  if (created.error) throw created.error;
  const id = created.data.user!.id;
  const up = await db.rpc("upsert_subscription_from_provider", {
    p_user_id: id,
    p_tier: tier,
    p_provider: "test",
    p_external_subscription_id: null,
    p_status: "active",
    p_current_period_end: null,
  });
  if (up.error) throw up.error;
  const anon = createClient(url, anonKey, { auth: { persistSession: false } });
  const signed = await anon.auth.signInWithPassword({ email, password });
  if (signed.error) throw signed.error;
  return { id, jwt: signed.data.session!.access_token };
}

export async function monthlyUsed(userId: string): Promise<number> {
  const { data } = await db
    .from("ai_usage_monthly")
    .select("queries_used")
    .eq("user_id", userId);
  return data?.[0]?.queries_used ?? 0;
}

export function sseResponse(chunks: string[]): Response {
  const enc = new TextEncoder();
  return new Response(
    new ReadableStream({
      start(c) {
        for (const chunk of chunks) c.enqueue(enc.encode(chunk));
        c.close();
      },
    }),
    { headers: { "Content-Type": "text/event-stream" } },
  );
}

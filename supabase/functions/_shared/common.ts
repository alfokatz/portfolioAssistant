// Piezas compartidas de las edge functions de la app (ai-chat, finnhub,
// revenuecat-webhook). Todo lo que tiene efectos (DB, red, reloj) entra por
// `Deps`, así los tests lo reemplazan sin mocks globales.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-porty-turn-id, " +
    "x-porty-purpose, x-porty-report-week",
};

export function json(
  status: number,
  body: unknown,
  extra: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", ...extra },
  });
}

/// Error tipado que la app sabe mostrar (ver `ProxyLimitException` en el
/// cliente). `type` es estable; `message` es solo diagnóstico.
export function typedError(
  status: number,
  type: string,
  message: string,
  extra: Record<string, unknown> = {},
): Response {
  return json(status, { error: { type, message, ...extra } });
}

export type Deps = {
  /// Cliente con service role (RPCs de cuota, caché, suscripciones).
  db: SupabaseClient;
  /// Devuelve el user id del JWT, o null si no es válido.
  authenticate: (jwt: string) => Promise<string | null>;
  fetch: typeof fetch;
  env: (name: string) => string | undefined;
  now: () => number;
  /// Tareas que siguen después de devolver la respuesta (registro de uso
  /// de un stream). En producción, EdgeRuntime.waitUntil.
  background: (task: Promise<unknown>) => void;
};

export function defaultDeps(): Deps {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const db = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return {
    db,
    authenticate: async (jwt: string) => {
      const { data, error } = await db.auth.getUser(jwt);
      if (error || !data.user) return null;
      return data.user.id;
    },
    fetch: (input, init) => fetch(input, init),
    env: (name) => Deno.env.get(name),
    now: () => Date.now(),
    background: (task) => {
      // deno-lint-ignore no-explicit-any
      const runtime = (globalThis as any).EdgeRuntime;
      if (runtime?.waitUntil) runtime.waitUntil(task);
      else task.catch((e) => console.error("background task failed", e));
    },
  };
}

/// El JWT del usuario, del header `Authorization: Bearer ...`.
export function bearer(req: Request): string | null {
  const header = req.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

export async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export const sleep = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));

// Proxy "delgado" de Chat Completions de OpenAI.
//
// El loop de tools sigue en la app (openai_genui_service.dart): cada ronda
// de un turno pasa por acá. Lo que se aplica en el servidor:
// - JWT de Supabase obligatorio (401 sin él);
// - la key de OpenAI vive solo en los secrets;
// - allowlist de modelo (model_prices.allowed), tope de salida, tope de body;
// - system prompt: solo el de la app (hash en allowlist) + el contexto de
//   cartera; el proxy no sirve como "GPT gratis" con un prompt arbitrario;
// - cuota: 1 consulta por turn_id, cobrada al llegar la respuesta final
//   (ronda sin tool calls); rondas y reintentos del mismo turno no cobran;
// - tope diario por plan, rate limit por usuario, tope de rondas por turno;
// - registro de tokens y costo por turno (ai_turn_usage).
// Streaming (stream: true) se reenvía tal cual, chunk a chunk.

import {
  bearer,
  corsHeaders,
  type Deps,
  json,
  sha256Hex,
  typedError,
} from "../_shared/common.ts";
import allowedPrompts from "./allowed_system_prompts.json" with { type: "json" };

export const config = {
  /// Tope de salida por ronda. La respuesta más larga de la app (un análisis
  /// de empresa en A2UI) ronda los 1.500 tokens.
  maxOutputTokens: 3000,
  /// Un turno de la app son 1-3 rondas con tools + la final; con el
  /// reintento transitorio, la ronda extra del chequeo de respuesta, el
  /// repair y hasta 3 reintentos por 429, el peor caso real queda en ~9.
  maxRoundsPerTurn: 10,
  /// Pedidos por minuto por usuario (un turno usa 2-4).
  ratePerMinute: 30,
  /// El body de un turno lleva el system prompt (~100 KB) y el historial.
  maxBodyBytes: 700_000,
  /// Único mensaje de sistema extra permitido: el contexto de cartera.
  pinnedContextPrefix: "PORTFOLIO_BRIEF",
  openAiUrl: "https://api.openai.com/v1/chat/completions",
};

/// Hashes SHA-256 de los system prompts que publica la app (uno por
/// versión en circulación). Los genera el test de Flutter
/// `system_prompt_allowlist_test.dart` (UPDATE_PROMPT_ALLOWLIST=1).
export const bundledPromptHashes = new Set<string>(
  (allowedPrompts as { hashes: string[] }).hashes,
);

type ChatMessage = { role?: string; content?: unknown };

function textOf(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((part) =>
        part && typeof part === "object" && typeof (part as { text?: unknown }).text === "string"
          ? (part as { text: string }).text
          : ""
      )
      .join("");
  }
  return "";
}

/// El primer mensaje tiene que ser un system prompt de la app (por hash) y
/// el único otro mensaje de sistema admitido es el contexto de cartera.
async function promptProblem(
  messages: ChatMessage[],
  allowedHashes: Set<string>,
): Promise<string | null> {
  if (messages.length === 0 || messages[0].role !== "system") {
    return "the first message must be the app system prompt";
  }
  const hash = await sha256Hex(textOf(messages[0].content));
  if (!allowedHashes.has(hash)) return "system prompt not allowed";
  for (const m of messages.slice(1)) {
    if (m.role !== "system") continue;
    if (!textOf(m.content).startsWith(config.pinnedContextPrefix)) {
      return "extra system messages are not allowed";
    }
  }
  return null;
}

const limitStatus: Record<string, [number, string]> = {
  quota_exceeded: [402, "Monthly query quota exceeded"],
  daily_limit: [429, "Daily query limit reached"],
  rate_limited: [429, "Too many requests"],
  too_many_rounds: [429, "Too many rounds for this turn"],
  turn_mismatch: [409, "turn_id belongs to another user"],
  model_not_allowed: [400, "Model not allowed"],
};

type Usage = { prompt: number; cached: number; completion: number };

function usageOf(u: unknown): Usage {
  const usage = (u ?? {}) as {
    prompt_tokens?: number;
    completion_tokens?: number;
    prompt_tokens_details?: { cached_tokens?: number };
  };
  return {
    prompt: usage.prompt_tokens ?? 0,
    cached: usage.prompt_tokens_details?.cached_tokens ?? 0,
    completion: usage.completion_tokens ?? 0,
  };
}

async function recordRound(
  deps: Deps,
  userId: string,
  turnId: string,
  model: string,
  usage: Usage,
  final: boolean,
) {
  const { error } = await deps.db.rpc("ai_record_round", {
    p_user_id: userId,
    p_turn_id: turnId,
    p_model: model,
    p_prompt_tokens: usage.prompt,
    p_cached_tokens: usage.cached,
    p_completion_tokens: usage.completion,
    p_final: final,
  });
  if (error) console.error("ai_record_round failed", error.message);
}

export async function handle(
  req: Request,
  deps: Deps,
  options: { allowedPromptHashes?: Set<string> } = {},
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  const turnId = req.headers.get("x-porty-turn-id") ?? "";
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(turnId)) {
    return typedError(400, "invalid_turn_id", "x-porty-turn-id header required");
  }

  const raw = await req.text();
  if (new TextEncoder().encode(raw).length > config.maxBodyBytes) {
    return typedError(413, "body_too_large", "Request body too large");
  }
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    return typedError(400, "invalid_json", "Body must be JSON");
  }

  const model = typeof body.model === "string" ? body.model : "";
  const messages = Array.isArray(body.messages) ? (body.messages as ChatMessage[]) : [];
  const problem = await promptProblem(
    messages,
    options.allowedPromptHashes ?? bundledPromptHashes,
  );
  if (problem) return typedError(403, "prompt_not_allowed", problem);

  const begin = await deps.db.rpc("ai_begin_request", {
    p_user_id: userId,
    p_turn_id: turnId,
    p_model: model,
    p_max_rounds: config.maxRoundsPerTurn,
    p_rate_per_minute: config.ratePerMinute,
  });
  if (begin.error) {
    console.error("ai_begin_request failed", begin.error.message);
    return typedError(503, "unavailable", "Quota service unavailable");
  }
  const verdict = begin.data as { ok: boolean; reason?: string } & Record<string, unknown>;
  if (!verdict.ok) {
    const reason = verdict.reason ?? "rejected";
    const [status, message] = limitStatus[reason] ?? [403, "Rejected"];
    const { ok: _ok, reason: _reason, ...extra } = verdict;
    return typedError(status, reason, message, extra);
  }

  // El servidor fija lo que no se negocia.
  const requested = Number(body.max_completion_tokens ?? body.max_tokens ?? config.maxOutputTokens);
  delete body.max_tokens;
  body.max_completion_tokens = Math.min(
    Number.isFinite(requested) && requested > 0 ? requested : config.maxOutputTokens,
    config.maxOutputTokens,
  );
  body.n = 1;
  body.store = false;
  const stream = body.stream === true;
  if (stream) body.stream_options = { include_usage: true };

  const apiKey = deps.env("OPENAI_API_KEY");
  if (!apiKey) return typedError(503, "unavailable", "OpenAI key not configured");

  const upstream = await deps.fetch(config.openAiUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify(body),
  });

  // Errores de OpenAI (429, 5xx…) pasan tal cual: la app ya sabe
  // reintentar el 429 con el mismo turn_id, que no vuelve a cobrar.
  if (!upstream.ok || !stream || !upstream.body) {
    const text = await upstream.text();
    if (upstream.ok) {
      try {
        const parsed = JSON.parse(text);
        const message = parsed?.choices?.[0]?.message ?? {};
        const final = !(Array.isArray(message.tool_calls) && message.tool_calls.length > 0);
        await recordRound(deps, userId, turnId, model, usageOf(parsed.usage), final);
      } catch (e) {
        console.error("could not parse OpenAI response", String(e));
      }
    }
    return new Response(text, {
      status: upstream.status,
      headers: { ...corsHeaders, "Content-Type": upstream.headers.get("Content-Type") ?? "application/json" },
    });
  }

  // Streaming: cada chunk sale apenas llega (sin buffer). En paralelo se lee
  // una copia para sacar el uso (último chunk, include_usage) y si hubo
  // tool calls; al cerrar el stream se registra la ronda.
  const decoder = new TextDecoder();
  let pending = "";
  let usage: Usage = { prompt: 0, cached: 0, completion: 0 };
  let sawToolCall = false;
  let resolveDone: () => void = () => {};
  const done = new Promise<void>((r) => (resolveDone = r));
  const inspect = (text: string) => {
    pending += text;
    const lines = pending.split("\n");
    pending = lines.pop() ?? "";
    for (const line of lines) {
      const data = line.startsWith("data:") ? line.slice(5).trim() : "";
      if (!data || data === "[DONE]") continue;
      try {
        const chunk = JSON.parse(data);
        if (chunk.usage) usage = usageOf(chunk.usage);
        if (chunk.choices?.[0]?.delta?.tool_calls) sawToolCall = true;
      } catch {
        // Un chunk partido se completa en la próxima vuelta.
      }
    }
  };
  const passthrough = new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      controller.enqueue(chunk);
      inspect(decoder.decode(chunk, { stream: true }));
    },
    flush() {
      inspect(decoder.decode() + "\n");
      resolveDone();
    },
  });
  deps.background(
    done.then(() => recordRound(deps, userId, turnId, model, usage, !sawToolCall)),
  );
  return new Response(upstream.body.pipeThrough(passthrough), {
    status: upstream.status,
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
    },
  });
}

export { json };

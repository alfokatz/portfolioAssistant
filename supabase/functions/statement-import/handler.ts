// statement-import: lee un CSV o PDF de un bróker y devuelve las posiciones
// para la vista previa de la app. No guarda nada: la app agrega las
// posiciones (como manuales) cuando el usuario confirma.
//
// POST /functions/v1/statement-import  JWT
//   { filename, mime_type?, content_base64 }
//   → 200 { source: "csv" | "ai", rows: ImportRow[], warnings: ImportWarning[] }
//
// 1. CSV con encabezados reconocibles: sin IA y sin cobrar.
// 2. Si no (PDF, CSV raro): IA, cobrando una consulta del cupo mensual con
//    el mismo mecanismo que el chat (`ai_begin_request` / `ai_record_round`).
//
// El contenido del archivo no se guarda ni se loguea.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { bearer, corsHeaders, type Deps, json, typedError } from "../_shared/common.ts";
import { aiConfig, extractWithAi, type FileInput, type Usage } from "./ai.ts";
import { parseCsv } from "./parse_csv.ts";
import { finalizeRows, type ImportWarning } from "./rows.ts";

export const handlerConfig = {
  /// Tamaño máximo del archivo (antes de base64).
  maxFileBytes: 2 * 1024 * 1024,
  /// Pedidos por usuario y minuto (con o sin IA).
  ratePerMinute: 6,
};

export type Verdict = { ok: boolean; reason?: string } & Record<string, unknown>;

/// Cupo y límite de pedidos (RPCs de 20260930120000_ai_proxy.sql).
export interface ImportQuota {
  /// `false` si pasó el límite de pedidos por minuto.
  rateOk(userId: string): Promise<boolean>;
  begin(userId: string, turnId: string, model: string): Promise<Verdict>;
  record(userId: string, turnId: string, model: string, usage: Usage): Promise<void>;
}

export type ImportDeps = Pick<Deps, "authenticate" | "fetch" | "env" | "now"> & {
  quota: ImportQuota;
  newId?: () => string;
};

const limitStatus: Record<string, number> = {
  quota_exceeded: 429,
  daily_quota_exceeded: 429,
  rate_limited: 429,
};

function log(fields: Record<string, unknown>) {
  // Nunca el contenido ni el nombre del archivo.
  console.log(JSON.stringify({ fn: "statement-import", ...fields }));
}

function decodeBase64(b64: string): Uint8Array | null {
  try {
    const bin = atob(b64.replace(/\s/g, ""));
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

/// Texto del archivo: UTF-8 si es válido; si no, Windows-1252 (los exportes
/// de Excel en español).
export function decodeText(bytes: Uint8Array): string {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return new TextDecoder("windows-1252").decode(bytes);
  }
}

export type FileKind = "pdf" | "text" | "unsupported";

export function fileKind(filename: string, bytes: Uint8Array): FileKind {
  const isPdf = bytes.length >= 4 && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 &&
    bytes[3] === 0x46; // %PDF
  if (isPdf) return "pdf";
  // xlsx/zip y xls (OLE): pedir que lo exporte a CSV.
  const isZip = bytes.length >= 2 && bytes[0] === 0x50 && bytes[1] === 0x4b;
  const isOle = bytes.length >= 4 && bytes[0] === 0xd0 && bytes[1] === 0xcf && bytes[2] === 0x11 && bytes[3] === 0xe0;
  if (isZip || isOle) return "unsupported";
  const ext = filename.toLowerCase().split(".").pop() ?? "";
  if (["csv", "txt", "tsv", "tab"].includes(ext) || ext === filename.toLowerCase()) return "text";
  return "unsupported";
}

export async function handle(req: Request, deps: ImportDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return typedError(405, "method_not_allowed", "POST only");

  const jwt = bearer(req);
  const userId = jwt ? await deps.authenticate(jwt) : null;
  if (!userId) return typedError(401, "unauthorized", "Missing or invalid JWT");

  const raw = await req.text();
  // base64 agranda 4/3; un poco de margen para el resto del JSON.
  if (raw.length > Math.ceil(handlerConfig.maxFileBytes * 4 / 3) + 4096) {
    return typedError(413, "file_too_large", "File too large", { max_bytes: handlerConfig.maxFileBytes });
  }
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    return typedError(400, "invalid_json", "Body must be JSON");
  }
  const filename = typeof body.filename === "string" && body.filename.trim()
    ? body.filename.trim().slice(0, 200)
    : "statement";
  const bytes = typeof body.content_base64 === "string" ? decodeBase64(body.content_base64) : null;
  if (!bytes || bytes.length === 0) return typedError(400, "invalid_file", "content_base64 is missing or invalid");
  if (bytes.length > handlerConfig.maxFileBytes) {
    return typedError(413, "file_too_large", "File too large", { max_bytes: handlerConfig.maxFileBytes });
  }

  const kind = fileKind(filename, bytes);
  if (kind === "unsupported") return typedError(415, "unsupported_type", "Use a CSV or PDF file");

  if (!(await deps.quota.rateOk(userId))) return typedError(429, "rate_limited", "Too many requests");

  const today = new Date(deps.now()).toISOString().slice(0, 10);

  // 1. CSV sin IA.
  let text: string | null = null;
  if (kind === "text") {
    text = decodeText(bytes);
    const csv = parseCsv(text);
    if (csv) {
      const done = finalizeRows(csv.rows, today);
      if (done.rows.length > 0) {
        log({ source: "csv", rows: done.rows.length });
        return json(200, { source: "csv", rows: done.rows, warnings: mergeWarnings(csv.warnings, done.warnings) });
      }
    }
  }

  // 2. IA.
  const apiKey = deps.env("OPENAI_API_KEY");
  if (!apiKey) return typedError(503, "unavailable", "AI not configured");
  const model = deps.env("STATEMENT_IMPORT_MODEL") || aiConfig.defaultModel;
  const turnId = `import:${deps.newId?.() ?? crypto.randomUUID()}`;

  let verdict: Verdict;
  try {
    verdict = await deps.quota.begin(userId, turnId, model);
  } catch (e) {
    console.error("statement-import quota failed", String(e));
    return typedError(503, "unavailable", "Quota service unavailable");
  }
  if (!verdict.ok) {
    const reason = verdict.reason ?? "rejected";
    const { ok: _ok, reason: _r, ...extra } = verdict;
    return typedError(limitStatus[reason] ?? 403, reason, "Import rejected", extra);
  }

  const input: FileInput = kind === "pdf"
    ? { kind: "pdf", filename, base64: (body.content_base64 as string).replace(/\s/g, "") }
    : { kind: "text", filename, text: text ?? decodeText(bytes) };
  const result = await extractWithAi(deps.fetch, apiKey, model, input);
  if (!result.ok) {
    log({ source: "ai", error: result.reason });
    // Lo que se consumió se registra igual (sin cerrar el turno, no cobra).
    return result.reason === "unavailable"
      ? typedError(503, "unavailable", "AI unavailable")
      : typedError(422, "nothing_found", "Could not read holdings from the file");
  }
  await deps.quota.record(userId, turnId, model, result.usage).catch((e) =>
    console.error("statement-import record failed", String(e))
  );

  const done = finalizeRows(result.rows, today);
  if (done.rows.length === 0) {
    log({ source: "ai", rows: 0 });
    return typedError(422, "nothing_found", "No holdings found in the file");
  }
  const warnings = result.truncated
    ? mergeWarnings(done.warnings, [{ type: "truncated", limit: done.rows.length }])
    : done.warnings;
  log({ source: "ai", rows: done.rows.length });
  return json(200, { source: "ai", rows: done.rows, warnings });
}

/// Une avisos sin repetir tipos (el de [a] gana).
function mergeWarnings(a: ImportWarning[], b: ImportWarning[]): ImportWarning[] {
  const seen = new Set(a.map((w) => w.type));
  return [...a, ...b.filter((w) => !seen.has(w.type))];
}

export function supabaseQuota(db: SupabaseClient): ImportQuota {
  return {
    async rateOk(userId) {
      const { data, error } = await db.rpc("rate_limit_hit", {
        p_user_id: userId,
        p_bucket: "statement_import",
        p_per_minute: handlerConfig.ratePerMinute,
      });
      if (error) throw new Error(`rate_limit_hit: ${error.message}`);
      return data === true;
    },
    async begin(userId, turnId, model) {
      const { data, error } = await db.rpc("ai_begin_request", {
        p_user_id: userId,
        p_turn_id: turnId,
        p_model: model,
        p_max_rounds: 1,
        p_rate_per_minute: 30,
      });
      if (error) throw new Error(`ai_begin_request: ${error.message}`);
      return data as Verdict;
    },
    async record(userId, turnId, model, usage) {
      const { error } = await db.rpc("ai_record_round", {
        p_user_id: userId,
        p_turn_id: turnId,
        p_model: model,
        p_prompt_tokens: usage.prompt,
        p_cached_tokens: usage.cached,
        p_completion_tokens: usage.completion,
        p_final: true,
      });
      if (error) throw new Error(`ai_record_round: ${error.message}`);
    },
  };
}

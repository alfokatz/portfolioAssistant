// Lectura de respuestas de la Responses API de OpenAI (texto, citas y
// búsquedas web), compartida por las funciones que buscan en la web.

export type ResponsesOutput = {
  /// `incomplete` = se cortó (p. ej. el razonamiento se comió el tope).
  status: string;
  text: string;
  /// `start`/`end`: rango del texto citado (índices del `output_text` de la
  /// parte donde vino; con varias partes, desplazados al texto completo).
  annotations: { url: string; title?: string; start?: number; end?: number }[];
  searchCalls: number;
  inputTokens: number;
  outputTokens: number;
};

// deno-lint-ignore no-explicit-any
export function readResponse(body: any): ResponsesOutput {
  let text = "";
  const annotations: ResponsesOutput["annotations"] = [];
  let searchCalls = 0;
  for (const item of Array.isArray(body?.output) ? body.output : []) {
    if (item?.type === "web_search_call") searchCalls++;
    if (item?.type !== "message") continue;
    for (const part of Array.isArray(item.content) ? item.content : []) {
      if (part?.type !== "output_text") continue;
      const offset = text.length;
      text += String(part.text ?? "");
      for (const a of Array.isArray(part.annotations) ? part.annotations : []) {
        if (a?.type !== "url_citation" || typeof a.url !== "string") continue;
        const start = Number(a.start_index);
        const end = Number(a.end_index);
        annotations.push({
          url: a.url,
          title: a.title,
          ...(Number.isFinite(start) && Number.isFinite(end) ? { start: offset + start, end: offset + end } : {}),
        });
      }
    }
  }
  // `text` sale recortado: los rangos se corren lo mismo.
  const leading = text.length - text.trimStart().length;
  if (leading > 0) {
    for (const a of annotations) {
      if (a.start !== undefined && a.end !== undefined) {
        a.start = Math.max(0, a.start - leading);
        a.end = Math.max(0, a.end - leading);
      }
    }
  }
  return {
    status: String(body?.status ?? ""),
    text: text.trim(),
    annotations,
    searchCalls,
    inputTokens: Number(body?.usage?.input_tokens ?? 0),
    outputTokens: Number(body?.usage?.output_tokens ?? 0),
  };
}

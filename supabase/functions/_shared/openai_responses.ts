// Lectura de respuestas de la Responses API de OpenAI (texto, citas y
// búsquedas web), compartida por las funciones que buscan en la web.

export type ResponsesOutput = {
  /// `incomplete` = se cortó (p. ej. el razonamiento se comió el tope).
  status: string;
  text: string;
  annotations: { url: string; title?: string }[];
  searchCalls: number;
  inputTokens: number;
  outputTokens: number;
};

// deno-lint-ignore no-explicit-any
export function readResponse(body: any): ResponsesOutput {
  let text = "";
  const annotations: { url: string; title?: string }[] = [];
  let searchCalls = 0;
  for (const item of Array.isArray(body?.output) ? body.output : []) {
    if (item?.type === "web_search_call") searchCalls++;
    if (item?.type !== "message") continue;
    for (const part of Array.isArray(item.content) ? item.content : []) {
      if (part?.type !== "output_text") continue;
      text += String(part.text ?? "");
      for (const a of Array.isArray(part.annotations) ? part.annotations : []) {
        if (a?.type === "url_citation" && typeof a.url === "string") annotations.push({ url: a.url, title: a.title });
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

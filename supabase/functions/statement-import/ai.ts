// Lectura con IA de lo que el lector de CSV no entiende (PDF, CSV sin
// encabezados claros). Arma el pedido a Chat Completions con salida
// estructurada y lee la respuesta. Lo que tiene efectos (fetch) entra por
// parámetro.

import type { ImportRow } from "./rows.ts";

export const aiConfig = {
  openAiUrl: "https://api.openai.com/v1/chat/completions",
  defaultModel: "gpt-6-luna",
  maxOutputTokens: 8000,
  /// Texto (CSV) que se manda como mucho; lo de más se corta.
  maxTextChars: 60_000,
};

export const systemPrompt = [
  "You extract investment holdings from a brokerage statement or export so a portfolio app can import them.",
  "Return ONLY the open holdings the account has now: stocks, ETFs, funds and crypto.",
  "Do not include cash balances, money market sweep, totals, interest, dividends or closed positions.",
  "If the document is a list of transactions instead of a holdings list, compute the current holdings: " +
  "net quantity per instrument, and as purchase_price the average price paid for the buys.",
  "ticker: the symbol as used by Yahoo Finance (AAPL, BRK-B; non-US listings with their Yahoo suffix, " +
  "for example GGAL.BA for Buenos Aires, SAN.MC for Madrid, BP.L for London; crypto as BTC-USD).",
  "quantity: units held (a positive number).",
  "purchase_price: average cost per unit in the instrument's currency. If only the total cost is shown, divide " +
  "it by the quantity. null if the document does not show it. Never use the current market price as cost.",
  "purchase_date: the purchase or open date as YYYY-MM-DD if shown (the earliest one for a holding bought " +
  "several times), otherwise null.",
  "currency: ISO code of the cost (USD, EUR, ARS...) if shown, otherwise null.",
  "Never invent values: when in doubt use null.",
].join("\n");

export const responseSchema = {
  type: "json_schema",
  json_schema: {
    name: "holdings",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: ["holdings"],
      properties: {
        holdings: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: ["ticker", "name", "quantity", "purchase_price", "purchase_date", "currency"],
            properties: {
              ticker: { type: "string" },
              name: { type: ["string", "null"] },
              quantity: { type: "number" },
              purchase_price: { type: ["number", "null"] },
              purchase_date: { type: ["string", "null"] },
              currency: { type: ["string", "null"] },
            },
          },
        },
      },
    },
  },
};

export type FileInput =
  | { kind: "pdf"; filename: string; base64: string }
  | { kind: "text"; filename: string; text: string };

export function buildRequest(model: string, file: FileInput): Record<string, unknown> {
  const content = file.kind === "pdf"
    ? [
      { type: "text", text: `File: ${file.filename}` },
      { type: "file", file: { filename: file.filename, file_data: `data:application/pdf;base64,${file.base64}` } },
    ]
    : [{
      type: "text",
      text: `File: ${file.filename}\n\n${file.text.slice(0, aiConfig.maxTextChars)}`,
    }];
  return {
    model,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content },
    ],
    response_format: responseSchema,
    max_completion_tokens: aiConfig.maxOutputTokens,
    n: 1,
    store: false,
  };
}

export type Usage = { prompt: number; cached: number; completion: number };

export type AiResult =
  | { ok: true; rows: ImportRow[]; usage: Usage; truncated: boolean }
  | { ok: false; reason: "unavailable" | "unreadable"; usage: Usage | null };

const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : null);
const str = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

// deno-lint-ignore no-explicit-any
export function readCompletion(body: any): AiResult {
  const usage: Usage = {
    prompt: Number(body?.usage?.prompt_tokens ?? 0),
    cached: Number(body?.usage?.prompt_tokens_details?.cached_tokens ?? 0),
    completion: Number(body?.usage?.completion_tokens ?? 0),
  };
  const choice = body?.choices?.[0];
  const text = choice?.message?.content;
  if (typeof text !== "string") return { ok: false, reason: "unreadable", usage };
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return { ok: false, reason: "unreadable", usage };
  }
  const list = (parsed as { holdings?: unknown })?.holdings;
  if (!Array.isArray(list)) return { ok: false, reason: "unreadable", usage };
  const rows: ImportRow[] = [];
  for (const item of list as Record<string, unknown>[]) {
    const ticker = str(item?.ticker);
    const quantity = num(item?.quantity);
    if (!ticker || quantity === null) continue;
    rows.push({
      ticker,
      name: str(item.name),
      quantity,
      purchase_price: num(item.purchase_price),
      purchase_date: str(item.purchase_date),
      currency: str(item.currency),
    });
  }
  return { ok: true, rows, usage, truncated: choice?.finish_reason === "length" };
}

export async function extractWithAi(
  fetchFn: typeof fetch,
  apiKey: string,
  model: string,
  file: FileInput,
): Promise<AiResult> {
  let res: Response;
  try {
    res = await fetchFn(aiConfig.openAiUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify(buildRequest(model, file)),
    });
  } catch {
    return { ok: false, reason: "unavailable", usage: null };
  }
  if (!res.ok) {
    await res.body?.cancel();
    return { ok: false, reason: "unavailable", usage: null };
  }
  try {
    return readCompletion(await res.json());
  } catch {
    return { ok: false, reason: "unreadable", usage: null };
  }
}

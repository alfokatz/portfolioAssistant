// statement-import: lector de CSV, normalización de filas y handler (con la
// IA y el cupo falsos). Sin red ni base: `deno test tests/statement_import_test.ts`.

import { assertEquals } from "jsr:@std/assert@1";
import {
  dateOrder,
  detectDelimiter,
  mapColumns,
  parseCsv,
  parseDate,
  parseNumber,
  splitLine,
} from "../statement-import/parse_csv.ts";
import { finalizeRows, normalizeTicker } from "../statement-import/rows.ts";
import { buildRequest, readCompletion } from "../statement-import/ai.ts";
import { fileKind, handle, type ImportDeps, type ImportQuota, type Verdict } from "../statement-import/handler.ts";

const today = "2026-10-16";

Deno.test("normalizeTicker: prefijos, .US, clases de acción y sufijos de bolsa", () => {
  assertEquals(normalizeTicker(" aapl "), "AAPL");
  assertEquals(normalizeTicker("NASDAQ:MSFT"), "MSFT");
  assertEquals(normalizeTicker("DASH.US"), "DASH");
  assertEquals(normalizeTicker("BRK.B"), "BRK-B");
  assertEquals(normalizeTicker("BP.L"), "BP.L");
  assertEquals(normalizeTicker("GGAL.BA"), "GGAL.BA");
  assertEquals(normalizeTicker("BTC-USD"), "BTC-USD");
  assertEquals(normalizeTicker("USD"), null);
  assertEquals(normalizeTicker("Total"), null);
  assertEquals(normalizeTicker("Apple Inc. common stock"), null);
});

Deno.test("parseNumber: formatos en inglés, español y con símbolos", () => {
  assertEquals(parseNumber("$1,234.56", false), 1234.56);
  assertEquals(parseNumber("1.234,56", true), 1234.56);
  assertEquals(parseNumber("1,5", false), 1.5);
  assertEquals(parseNumber("1,5", true), 1.5);
  assertEquals(parseNumber("1,234", false), 1234);
  assertEquals(parseNumber("1.234", true), 1234);
  assertEquals(parseNumber("(12.50)", false), -12.5);
  assertEquals(parseNumber("USD 189.20", false), 189.2);
  assertEquals(parseNumber("--", false), null);
  assertEquals(parseNumber("", false), null);
});

Deno.test("splitLine y detectDelimiter", () => {
  assertEquals(splitLine('AAPL,"Apple, Inc.",10', ","), ["AAPL", "Apple, Inc.", "10"]);
  assertEquals(splitLine('"say ""hi""";2', ";"), ['say "hi"', "2"]);
  assertEquals(detectDelimiter(["a;b;c", "1;2,5;3", "4;5;6"]), ";");
  assertEquals(detectDelimiter(["a\tb\tc", "1\t2\t3"]), "\t");
  assertEquals(detectDelimiter(["a,b,c", "1,2,3"]), ",");
});

Deno.test("mapColumns: sinónimos y preferencia del más específico", () => {
  const m = mapColumns(["Symbol", "Description", "Quantity", "Price", "Average Cost", "Date Acquired"])!;
  assertEquals(m.ticker, 0);
  assertEquals(m.name, 1);
  assertEquals(m.quantity, 2);
  // "Average Cost" gana sobre "Price" (que suele ser el precio de hoy).
  assertEquals(m.price, 4);
  assertEquals(m.date, 5);
  assertEquals(mapColumns(["Especie", "Cantidad", "PPC"])!.price, 2);
  assertEquals(mapColumns(["Nombre", "Valor"]), null);
});

Deno.test("dateOrder y parseDate", () => {
  assertEquals(dateOrder(["15/03/2024", "01/02/2024"]), { order: "dmy", ambiguous: false });
  assertEquals(dateOrder(["03/15/2024", "01/02/2024"]), { order: "mdy", ambiguous: false });
  assertEquals(dateOrder(["01/02/2024"]), { order: "dmy", ambiguous: true });
  assertEquals(dateOrder(["2024-01-02"]), { order: "dmy", ambiguous: false });
  assertEquals(parseDate("01/02/2024", "dmy"), "2024-02-01");
  assertEquals(parseDate("01/02/2024", "mdy"), "2024-01-02");
  assertEquals(parseDate("2024-03-15T10:00:00", "dmy"), "2024-03-15");
  assertEquals(parseDate("20240315", "dmy"), "2024-03-15");
  assertEquals(parseDate("31/02/2024", "dmy"), null);
});

Deno.test("parseCsv: exporte en inglés con título antes de la tabla", () => {
  const csv = [
    "Account Summary,,,",
    "Account,U1234567,,",
    "",
    "Symbol,Description,Quantity,Cost Basis,Date Acquired",
    'AAPL,"Apple, Inc.",10,"1,800.00",03/15/2024',
    "BRK.B,Berkshire Hathaway B,2.5,1000,01/02/2023",
    "CASH,Cash & Sweep,1500,,",
    "Total,,,2800,",
  ].join("\n");
  const r = parseCsv(csv)!;
  assertEquals(r.rows.length, 2);
  assertEquals(r.rows[0], {
    ticker: "AAPL",
    name: "Apple, Inc.",
    quantity: 10,
    purchase_price: 180,
    purchase_date: "2024-03-15",
    currency: null,
  });
  assertEquals(r.rows[1].ticker, "BRK-B");
  assertEquals(r.rows[1].purchase_price, 400);
  assertEquals(r.rows[1].purchase_date, "2023-01-02");
  assertEquals(r.warnings, [{ type: "cash_skipped", count: 1 }]);
});

Deno.test("parseCsv: exporte en español con punto y coma y coma decimal", () => {
  const csv = [
    "Especie;Cantidad;Precio promedio;Moneda;Fecha",
    "GGAL.BA;100;1.234,50;ARS;15/03/2024",
    "SPY;3;512,10;USD;01/02/2024",
  ].join("\r\n");
  const r = parseCsv(csv)!;
  assertEquals(r.rows.map((x) => [x.ticker, x.quantity, x.purchase_price, x.currency, x.purchase_date]), [
    ["GGAL.BA", 100, 1234.5, "ARS", "2024-03-15"],
    ["SPY", 3, 512.1, "USD", "2024-02-01"],
  ]);
  assertEquals(r.warnings, []);
});

Deno.test("parseCsv: sin columnas reconocibles devuelve null (sigue la IA)", () => {
  assertEquals(parseCsv("foo,bar\n1,2\n3,4"), null);
  assertEquals(parseCsv("Symbol,Quantity\n"), null);
});

Deno.test("finalizeRows: descarta lo inválido, limpia fechas futuras y avisa monedas", () => {
  const { rows, warnings } = finalizeRows([
    { ticker: "aapl", name: " Apple ", quantity: 1, purchase_price: 100, purchase_date: "2024-01-01", currency: "usd" },
    { ticker: "MSFT", name: null, quantity: 0, purchase_price: 10, purchase_date: null, currency: null },
    { ticker: "SAN.MC", name: null, quantity: 5, purchase_price: -1, purchase_date: "2030-01-01", currency: "EUR" },
  ], today);
  assertEquals(rows, [
    { ticker: "AAPL", name: "Apple", quantity: 1, purchase_price: 100, purchase_date: "2024-01-01", currency: "USD" },
    { ticker: "SAN.MC", name: null, quantity: 5, purchase_price: null, purchase_date: null, currency: "EUR" },
  ]);
  assertEquals(warnings, [{ type: "skipped_rows", count: 1 }, { type: "non_usd_currency", currencies: ["EUR"] }]);
});

Deno.test("buildRequest: PDF como archivo, texto recortado, salida estructurada", () => {
  const pdf = buildRequest("m", { kind: "pdf", filename: "a.pdf", base64: "QUJD" });
  // deno-lint-ignore no-explicit-any
  const content = (pdf.messages as any[])[1].content;
  assertEquals(content[1].file.file_data, "data:application/pdf;base64,QUJD");
  // deno-lint-ignore no-explicit-any
  assertEquals((pdf.response_format as any).json_schema.strict, true);
  const text = buildRequest("m", { kind: "text", filename: "a.csv", text: "x".repeat(100_000) });
  // deno-lint-ignore no-explicit-any
  assertEquals(((text.messages as any[])[1].content[0].text as string).length < 61_000, true);
});

Deno.test("readCompletion: lee las filas, el uso y si se cortó", () => {
  const ok = readCompletion({
    choices: [{
      finish_reason: "length",
      message: {
        content: JSON.stringify({
          holdings: [
            { ticker: "VOO", name: "Vanguard", quantity: 2, purchase_price: 400, purchase_date: null, currency: "USD" },
            { ticker: "", name: null, quantity: 1, purchase_price: null, purchase_date: null, currency: null },
          ],
        }),
      },
    }],
    usage: { prompt_tokens: 10, completion_tokens: 5, prompt_tokens_details: { cached_tokens: 2 } },
  });
  assertEquals(ok.ok, true);
  if (ok.ok) {
    assertEquals(ok.rows.length, 1);
    assertEquals(ok.usage, { prompt: 10, cached: 2, completion: 5 });
    assertEquals(ok.truncated, true);
  }
  assertEquals(readCompletion({ choices: [{ message: { content: "no json" } }] }).ok, false);
});

Deno.test("fileKind: PDF por contenido, Excel no, CSV por extensión", () => {
  const enc = (s: string) => new TextEncoder().encode(s);
  assertEquals(fileKind("x.bin", enc("%PDF-1.7")), "pdf");
  assertEquals(fileKind("x.xlsx", new Uint8Array([0x50, 0x4b, 3, 4])), "unsupported");
  assertEquals(fileKind("x.csv", enc("a,b")), "text");
  assertEquals(fileKind("x.docx", enc("a,b")), "unsupported");
});

// ── Handler ──

type Calls = { begin: number; record: number; openai: number };

function deps(opts: {
  verdict?: Verdict;
  openai?: (body: Record<string, unknown>) => Response;
  rateOk?: boolean;
  user?: string | null;
} = {}): { deps: ImportDeps; calls: Calls } {
  const calls: Calls = { begin: 0, record: 0, openai: 0 };
  const quota: ImportQuota = {
    rateOk: () => Promise.resolve(opts.rateOk ?? true),
    begin: () => {
      calls.begin++;
      return Promise.resolve(opts.verdict ?? { ok: true });
    },
    record: () => {
      calls.record++;
      return Promise.resolve();
    },
  };
  return {
    calls,
    deps: {
      authenticate: () => Promise.resolve(opts.user === undefined ? "user-1" : opts.user),
      env: (name) => (name === "OPENAI_API_KEY" ? "sk-test" : undefined),
      now: () => Date.parse(`${today}T12:00:00Z`),
      newId: () => "fixed",
      quota,
      fetch: (_input, init) => {
        calls.openai++;
        const body = JSON.parse(String(init?.body ?? "{}"));
        return Promise.resolve(opts.openai?.(body) ?? new Response("{}", { status: 500 }));
      },
    },
  };
}

function request(filename: string, content: string | Uint8Array): Request {
  const bytes = typeof content === "string" ? new TextEncoder().encode(content) : content;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return new Request("http://local/statement-import", {
    method: "POST",
    headers: { Authorization: "Bearer jwt", "Content-Type": "application/json" },
    body: JSON.stringify({ filename, content_base64: btoa(bin) }),
  });
}

const aiHoldings = (holdings: unknown[]) =>
  new Response(
    JSON.stringify({
      choices: [{ finish_reason: "stop", message: { content: JSON.stringify({ holdings }) } }],
      usage: { prompt_tokens: 100, completion_tokens: 20 },
    }),
    { status: 200 },
  );

Deno.test("handler: CSV reconocible sale sin IA ni cupo", async () => {
  const { deps: d, calls } = deps();
  const res = await handle(request("pos.csv", "Symbol,Quantity,Avg Cost\nAAPL,10,150\n"), d);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.source, "csv");
  assertEquals(body.rows[0].ticker, "AAPL");
  assertEquals(calls, { begin: 0, record: 0, openai: 0 });
});

Deno.test("handler: PDF va a la IA y cobra una consulta", async () => {
  let sent: Record<string, unknown> = {};
  const { deps: d, calls } = deps({
    openai: (body) => {
      sent = body;
      return aiHoldings([
        {
          ticker: "MSFT",
          name: "Microsoft",
          quantity: 3,
          purchase_price: 300,
          purchase_date: "2024-05-01",
          currency: "USD",
        },
      ]);
    },
  });
  const res = await handle(request("statement.pdf", "%PDF-1.4 fake"), d);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.source, "ai");
  assertEquals(body.rows, [{
    ticker: "MSFT",
    name: "Microsoft",
    quantity: 3,
    purchase_price: 300,
    purchase_date: "2024-05-01",
    currency: "USD",
  }]);
  assertEquals(calls, { begin: 1, record: 1, openai: 1 });
  assertEquals(sent.model, "gpt-6-luna");
});

Deno.test("handler: sin cupo no llama a la IA", async () => {
  const { deps: d, calls } = deps({ verdict: { ok: false, reason: "quota_exceeded", queries_limit: 20 } });
  const res = await handle(request("statement.pdf", "%PDF-1.4"), d);
  assertEquals(res.status, 429);
  assertEquals((await res.json()).error.type, "quota_exceeded");
  assertEquals(calls.openai, 0);
});

Deno.test("handler: la IA no encuentra nada → nothing_found y no se cobra de más", async () => {
  const { deps: d, calls } = deps({ openai: () => aiHoldings([]) });
  const res = await handle(request("x.pdf", "%PDF-1.4"), d);
  assertEquals(res.status, 422);
  assertEquals((await res.json()).error.type, "nothing_found");
  assertEquals(calls.record, 1);
});

Deno.test("handler: OpenAI caído → unavailable sin registrar uso", async () => {
  const { deps: d, calls } = deps({ openai: () => new Response("boom", { status: 500 }) });
  const res = await handle(request("x.pdf", "%PDF-1.4"), d);
  assertEquals(res.status, 503);
  assertEquals(calls.record, 0);
});

Deno.test("handler: auth, tipo de archivo, tamaño y límite por minuto", async () => {
  assertEquals((await handle(request("a.csv", "a"), deps({ user: null }).deps)).status, 401);
  assertEquals((await handle(request("a.xlsx", new Uint8Array([0x50, 0x4b, 3, 4])), deps().deps)).status, 415);
  assertEquals((await handle(request("a.csv", "Symbol,Quantity\nA,1"), deps({ rateOk: false }).deps)).status, 429);
  const big = new Uint8Array(2 * 1024 * 1024 + 10).fill(65);
  assertEquals((await handle(request("a.csv", big), deps().deps)).status, 413);
});

// ── Capturas y lo que escribe el usuario (aha moment, fases 5 y 6) ──

const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);

function noteRequest(note: unknown): Request {
  return new Request("http://local/statement-import", {
    method: "POST",
    headers: { Authorization: "Bearer jwt", "Content-Type": "application/json" },
    body: JSON.stringify({ note }),
  });
}

Deno.test("fileKind: capturas PNG/JPG/WebP por contenido; HEIC no", () => {
  assertEquals(fileKind("captura.png", png), "image");
  assertEquals(fileKind("foto", new Uint8Array([0xff, 0xd8, 0xff, 0xe0])), "image");
  const webp = new TextEncoder().encode("RIFF\x00\x00\x00\x00WEBPVP8 ");
  assertEquals(fileKind("x.webp", webp), "image");
  const heic = new TextEncoder().encode("\x00\x00\x00\x18ftypheic");
  assertEquals(fileKind("x.heic", heic), "unsupported");
});

Deno.test("handler: una captura va a la IA como imagen; sin unidades, con el valor", async () => {
  let sent: Record<string, unknown> = {};
  const { deps: d, calls } = deps({
    openai: (body) => {
      sent = body;
      return aiHoldings([
        { ticker: "VOO", name: null, quantity: 4, purchase_price: null, purchase_date: null, currency: null, amount: null },
        { ticker: "NVDA", name: null, quantity: null, purchase_price: null, purchase_date: null, currency: null, amount: 1250 },
      ]);
    },
  });
  const res = await handle(request("IMG_1234.png", png), d);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.rows.map((r: { ticker: string; quantity: number; amount: number | null }) => [r.ticker, r.quantity, r.amount]), [
    ["VOO", 4, null],
    ["NVDA", 0, 1250],
  ]);
  assertEquals(calls, { begin: 1, record: 1, openai: 1 });
  const messages = sent.messages as { role: string; content: unknown }[];
  const parts = messages[1].content as { type: string; image_url?: { url: string } }[];
  assertEquals(parts[1].type, "image_url");
  assertEquals(parts[1].image_url!.url.startsWith("data:image/png;base64,"), true);
  assertEquals(String(messages[0].content).includes("screenshot"), true);
});

Deno.test("handler: lo que escribe el usuario (nota) va a la IA con sus instrucciones", async () => {
  let sent: Record<string, unknown> = {};
  const { deps: d, calls } = deps({
    openai: (body) => {
      sent = body;
      return aiHoldings([
        { ticker: "VOO", name: null, quantity: 10, purchase_price: null, purchase_date: null, currency: null, amount: null },
        { ticker: "QQQ", name: null, quantity: null, purchase_price: null, purchase_date: null, currency: null, amount: 2000 },
        { ticker: "NVDA", name: null, quantity: null, purchase_price: null, purchase_date: null, currency: null, amount: null },
      ]);
    },
  });
  const res = await handle(noteRequest("10 VOO, 2000 dólares en QQQ y algo de NVDA"), d);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.source, "ai");
  assertEquals(body.rows.map((r: { ticker: string; quantity: number; amount: number | null }) => [r.ticker, r.quantity, r.amount]), [
    ["VOO", 10, null],
    ["QQQ", 0, 2000],
    // Sin cantidad ni monto: la completa en la vista previa.
    ["NVDA", 0, null],
  ]);
  assertEquals(calls, { begin: 1, record: 1, openai: 1 });
  const messages = sent.messages as { role: string; content: unknown }[];
  assertEquals(String(messages[0].content).includes("describing what they own"), true);
  const parts = messages[1].content as { type: string; text: string }[];
  assertEquals(parts[0].text, "10 VOO, 2000 dólares en QQQ y algo de NVDA");
});

Deno.test("handler: nota vacía, larga o sin cupo", async () => {
  assertEquals((await handle(noteRequest("  "), deps().deps)).status, 400);
  assertEquals((await handle(noteRequest("x".repeat(2001)), deps().deps)).status, 413);
  const { deps: d, calls } = deps({ verdict: { ok: false, reason: "quota_exceeded" } });
  const res = await handle(noteRequest("VOO"), d);
  assertEquals(res.status, 429);
  assertEquals(calls.openai, 0);
});

Deno.test("en un archivo, una fila sin cantidad se sigue descartando", () => {
  const { rows } = finalizeRows(
    [{ ticker: "AAPL", name: null, quantity: 0, purchase_price: null, purchase_date: null, currency: null }],
    today,
  );
  assertEquals(rows, []);
  const ok = readCompletion({
    choices: [{
      message: {
        content: JSON.stringify({
          holdings: [{ ticker: "AAPL", name: null, quantity: null, purchase_price: null, purchase_date: null, currency: null, amount: 5 }],
        }),
      },
    }],
  });
  assertEquals(ok.ok && ok.rows.length, 0);
});

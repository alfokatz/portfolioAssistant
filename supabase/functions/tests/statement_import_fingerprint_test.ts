// statement-import: huella anónima del formato y lo que se loguea. Que
// nunca salga contenido del archivo. Sin red:
// `deno test tests/statement_import_fingerprint_test.ts`.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { fingerprint, headerRow } from "../statement-import/fingerprint.ts";
import { extensionOf, handle, type ImportDeps } from "../statement-import/handler.ts";

Deno.test("headerRow: la fila de encabezados, no el título ni los datos", () => {
  const csv = [
    "Cuenta de Juan Pérez - Comitente 4455",
    "Ticker;Cantidad;Último precio;Valuación",
    "GGAL;100;4210,5;421050",
  ].join("\n");
  assertEquals(headerRow(csv), ["ticker", "cantidad", "ultimoprecio", "valuacion"]);
  assertEquals(headerRow(""), null);
});

Deno.test("fingerprint: hash estable y desconocidos como '?'", async () => {
  const a = await fingerprint("Symbol,Juan Perez,Quantity,Rara\nAAPL,x,1,2");
  const b = await fingerprint("Symbol,Juan Perez,Quantity,Rara\nMSFT,y,3,4");
  assert(a && b);
  assertEquals(a.hash, b.hash);
  assertEquals(a.hash.length, 12);
  assertEquals(a.cols, 4);
  assertEquals(a.known, "symbol|?|quantity|?");
});

Deno.test("extensionOf: solo extensiones conocidas", () => {
  assertEquals(extensionOf("Tenencia Juan.XLSX"), "xlsx");
  assertEquals(extensionOf("cuenta-juan-perez"), "other");
  assertEquals(extensionOf("x.exe"), "other");
});

function deps(): ImportDeps {
  return {
    authenticate: () => Promise.resolve("user-1"),
    env: () => undefined,
    now: () => Date.parse("2026-10-16T12:00:00Z"),
    quota: {
      rateOk: () => Promise.resolve(true),
      begin: () => Promise.resolve({ ok: true }),
      record: () => Promise.resolve(),
    },
    fetch: () => Promise.resolve(new Response("{}", { status: 500 })),
  };
}

function request(filename: string, content: string): Request {
  return new Request("http://local/statement-import", {
    method: "POST",
    headers: { Authorization: "Bearer jwt", "Content-Type": "application/json" },
    body: JSON.stringify({ filename, content_base64: btoa(unescape(encodeURIComponent(content))) }),
  });
}

async function captureLogs(fn: () => Promise<unknown>): Promise<string[]> {
  const lines: string[] = [];
  const original = console.log;
  console.log = (...args: unknown[]) => lines.push(args.map(String).join(" "));
  try {
    await fn();
  } finally {
    console.log = original;
  }
  return lines;
}

Deno.test("handler: el log dice formato y extensión, nunca el contenido ni el nombre", async () => {
  const ok = await captureLogs(() =>
    handle(request("tenencia-juan-perez.csv", "Cuenta Juan Perez 4455\nSymbol,Quantity\nAAPL,3"), deps())
  );
  assertEquals(ok.length, 1);
  const entry = JSON.parse(ok[0]);
  assertEquals(entry.source, "csv");
  assertEquals(entry.format, "generic");
  assertEquals(entry.ext, "csv");
  assertEquals(entry.fmt.known, "symbol|quantity");

  // Sin columnas reconocibles va a la IA (acá sin key: 503), pero antes de
  // salir no loguea nada del archivo.
  const failed = await captureLogs(() => handle(request("juan.csv", "Juan Perez,AAPL\nMaria,3"), deps()));
  for (const line of [...ok, ...failed]) {
    assert(!/juan|perez|4455|aapl|maria/i.test(line), line);
  }
});

Deno.test("handler: un tipo no soportado queda registrado", async () => {
  const logs = await captureLogs(() => handle(request("x.docx", "PK"), deps()));
  assertEquals(JSON.parse(logs[0]), {
    fn: "statement-import",
    kind: "unsupported",
    ext: "other",
    outcome: "unsupported_type",
  });
});

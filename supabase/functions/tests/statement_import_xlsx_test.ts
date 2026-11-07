// statement-import: lector de .xlsx (zip + XML) y su paso por el handler.
// Los libros se arman acá mismo con un zip mínimo. Sin red:
// `deno test tests/statement_import_xlsx_test.ts`.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { handle, type ImportDeps } from "../statement-import/handler.ts";
import {
  columnIndex,
  dateStyles,
  readXlsx,
  serialToIso,
  sharedStrings,
  sheetText,
  unescapeXml,
  xlsxLimits,
} from "../statement-import/xlsx.ts";

const enc = (s: string) => new TextEncoder().encode(s);

async function deflateRaw(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data.slice()]).stream().pipeThrough(new CompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/// Un zip con [files] (deflate o guardados). Sin CRC: el lector no lo mira.
async function zip(files: Record<string, string | Uint8Array>, deflate = true): Promise<Uint8Array> {
  const local: number[] = [];
  const central: number[] = [];
  const le16 = (n: number) => [n & 0xff, (n >> 8) & 0xff];
  const le32 = (n: number) => [n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >>> 24) & 0xff];
  for (const [name, content] of Object.entries(files)) {
    const raw = typeof content === "string" ? enc(content) : content;
    const data = deflate ? await deflateRaw(raw) : raw;
    const nameBytes = enc(name);
    const offset = local.length;
    const method = deflate ? 8 : 0;
    local.push(
      ...le32(0x04034b50),
      ...le16(20),
      ...le16(0),
      ...le16(method),
      ...le32(0),
      ...le32(0),
      ...le32(data.length),
      ...le32(raw.length),
      ...le16(nameBytes.length),
      ...le16(0),
      ...nameBytes,
      ...data,
    );
    central.push(
      ...le32(0x02014b50),
      ...le16(20),
      ...le16(20),
      ...le16(0),
      ...le16(method),
      ...le32(0),
      ...le32(0),
      ...le32(data.length),
      ...le32(raw.length),
      ...le16(nameBytes.length),
      ...le16(0),
      ...le16(0),
      ...le16(0),
      ...le16(0),
      ...le32(0),
      ...le32(offset),
      ...nameBytes,
    );
  }
  const count = Object.keys(files).length;
  const end = [
    ...le32(0x06054b50),
    ...le16(0),
    ...le16(0),
    ...le16(count),
    ...le16(count),
    ...le32(central.length),
    ...le32(local.length),
    ...le16(0),
  ];
  return new Uint8Array([...local, ...central, ...end]);
}

/// Un libro con una hoja de títulos (sin tabla) y otra con las posiciones.
function workbook(sheet2: string, extra: Record<string, string> = {}): Record<string, string> {
  return {
    "[Content_Types].xml": "<Types/>",
    "xl/workbook.xml": `<workbook><sheets>
      <sheet name="Resumen" sheetId="1" r:id="rId1"/>
      <sheet name="Tenencia" sheetId="2" r:id="rId2"/>
    </sheets></workbook>`,
    "xl/_rels/workbook.xml.rels": `<Relationships>
      <Relationship Id="rId1" Type="ws" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="ws" Target="/xl/worksheets/sheet2.xml"/>
    </Relationships>`,
    "xl/sharedStrings.xml": `<sst>
      <si><t>Cuenta 1234</t></si>
      <si><t>Especie</t></si>
      <si><t>Cantidad</t></si>
      <si><t>Precio promedio</t></si>
      <si><t>Fecha de compra</t></si>
      <si><r><t>Apple</t></r><r><t xml:space="preserve"> Inc.</t></r></si>
      <si><t>Descripción</t></si>
    </sst>`,
    "xl/styles.xml": `<styleSheet>
      <numFmts count="1"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/></numFmts>
      <cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="164"/><xf numFmtId="4"/></cellXfs>
    </styleSheet>`,
    "xl/worksheets/sheet1.xml": `<worksheet><sheetData>
      <row r="1"><c r="A1" t="s"><v>0</v></c></row>
    </sheetData></worksheet>`,
    "xl/worksheets/sheet2.xml": sheet2,
    ...extra,
  };
}

const holdings = `<worksheet><sheetData>
  <row r="1"><c r="A1" t="s"><v>0</v></c></row>
  <row r="3">
    <c r="A3" t="s"><v>1</v></c><c r="B3" t="s"><v>2</v></c><c r="C3" t="s"><v>3</v></c>
    <c r="D3" t="s"><v>4</v></c><c r="E3" t="s"><v>6</v></c>
  </row>
  <row r="4">
    <c r="A4" t="inlineStr"><is><t>AAPL</t></is></c><c r="B4"><v>12.5</v></c>
    <c r="C4" s="2"><v>150.25</v></c><c r="D4" s="1"><v>45366</v></c><c r="E4" t="s"><v>5</v></c>
  </row>
  <row r="5">
    <c r="A5" t="str"><v>GGAL.BA</v></c><c r="B5"><v>300</v></c><c r="C5"><v>4210.5</v></c>
  </row>
</sheetData></worksheet>`;

Deno.test("xlsx: celdas, textos compartidos, fechas y columnas", () => {
  assertEquals(columnIndex("A1"), 0);
  assertEquals(columnIndex("AB12"), 27);
  assertEquals(unescapeXml("S&amp;P &lt;500&gt; &#233;&#x41;"), "S&P <500> éA");
  assertEquals(serialToIso(45366), "2024-03-15");
  assertEquals(serialToIso(0), null);
  assertEquals(sharedStrings("<sst><si><t>a</t></si><si/><si><r><t>b</t></r><r><t>c</t></r></si></sst>"), [
    "a",
    "",
    "bc",
  ]);
  const dates = dateStyles(
    `<numFmts><numFmt numFmtId="164" formatCode="d/m/yy"/><numFmt numFmtId="165" formatCode="#,##0.00 &quot;dly&quot;"/></numFmts>
     <cellXfs><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/><xf numFmtId="165"/></cellXfs>`,
  );
  assertEquals([...dates], [1, 2]);
  // Celdas vacías en el medio y una con comillas.
  const text = sheetText(
    `<row r="1"><c r="A1" t="inlineStr"><is><t>a "b"</t></is></c><c r="C1"><v>3</v></c></row><row r="2"/>`,
    [],
    new Set(),
  );
  assertEquals(text, '"a ""b"""\t\t3');
});

Deno.test("xlsx: lee el libro (deflate y guardado) en orden de hojas", async () => {
  for (const deflate of [true, false]) {
    const sheets = await readXlsx(await zip(workbook(holdings), deflate));
    assert(sheets);
    assertEquals(sheets.map((s) => s.name), ["Resumen", "Tenencia"]);
    const lines = sheets[1].text.split("\n");
    assertEquals(lines[1], "Especie\tCantidad\tPrecio promedio\tFecha de compra\tDescripción");
    assertEquals(lines[2], "AAPL\t12.5\t150.25\t2024-03-15\tApple Inc.");
  }
});

Deno.test("xlsx: lo que no es un libro o se infla de más devuelve null", async () => {
  assertEquals(await readXlsx(enc("PK no es un zip")), null);
  assertEquals(await readXlsx(await zip({ "word/document.xml": "<w/>" })), null);
  // Un zip bomb chico: 30 MB de ceros en una hoja.
  const bomb = new Uint8Array(xlsxLimits.maxEntryBytes + 1024);
  assertEquals(
    await readXlsx(await zip(workbook("", { "xl/worksheets/sheet2.xml": bomb as unknown as string }))),
    null,
  );
});

// ── Handler ──

function deps(calls: { openai: number; begin: number }): ImportDeps {
  return {
    authenticate: () => Promise.resolve("user-1"),
    env: (name) => (name === "OPENAI_API_KEY" ? "sk-test" : undefined),
    now: () => Date.parse("2026-10-16T12:00:00Z"),
    newId: () => "fixed",
    quota: {
      rateOk: () => Promise.resolve(true),
      begin: () => {
        calls.begin++;
        return Promise.resolve({ ok: true });
      },
      record: () => Promise.resolve(),
    },
    fetch: (_input, init) => {
      calls.openai++;
      const body = JSON.parse(String(init?.body ?? "{}"));
      const text = JSON.stringify(body.messages);
      // La IA recibe las hojas como texto con su nombre.
      assert(text.includes("# Tenencia"));
      return Promise.resolve(
        new Response(
          JSON.stringify({
            choices: [{
              finish_reason: "stop",
              message: {
                content: JSON.stringify({
                  holdings: [{
                    ticker: "VOO",
                    name: null,
                    quantity: 3,
                    purchase_price: 400,
                    purchase_date: null,
                    currency: "USD",
                    amount: null,
                  }],
                }),
              },
            }],
            usage: { prompt_tokens: 10, completion_tokens: 5 },
          }),
        ),
      );
    },
  };
}

function request(filename: string, bytes: Uint8Array): Request {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return new Request("http://local/statement-import", {
    method: "POST",
    headers: { Authorization: "Bearer jwt", "Content-Type": "application/json" },
    body: JSON.stringify({ filename, content_base64: btoa(bin) }),
  });
}

Deno.test("handler: un .xlsx con columnas claras sale sin IA ni cupo", async () => {
  const calls = { openai: 0, begin: 0 };
  const res = await handle(request("tenencia.xlsx", await zip(workbook(holdings))), deps(calls));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.source, "csv");
  assertEquals(body.rows[0], {
    ticker: "AAPL",
    name: "Apple Inc.",
    quantity: 12.5,
    purchase_price: 150.25,
    purchase_date: "2024-03-15",
    currency: null,
  });
  assertEquals(body.rows[1].ticker, "GGAL.BA");
  assertEquals(body.rows[1].purchase_price, 4210.5);
  assertEquals(calls, { openai: 0, begin: 0 });
});

Deno.test("handler: un .xlsx sin encabezados claros va a la IA como texto", async () => {
  const calls = { openai: 0, begin: 0 };
  const odd = `<worksheet><sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Vanguard S&amp;P 500</t></is></c><c r="B1"><v>3</v></c></row>
  </sheetData></worksheet>`;
  const res = await handle(request("raro.xlsx", await zip(workbook(odd))), deps(calls));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.source, "ai");
  assertEquals(body.rows[0].ticker, "VOO");
  assertEquals(calls, { openai: 1, begin: 1 });
});

Deno.test("handler: un zip que no es Excel se rechaza sin cobrar", async () => {
  const calls = { openai: 0, begin: 0 };
  const res = await handle(request("x.xlsx", await zip({ "a.txt": "hola" })), deps(calls));
  assertEquals(res.status, 415);
  assertEquals(calls, { openai: 0, begin: 0 });
});

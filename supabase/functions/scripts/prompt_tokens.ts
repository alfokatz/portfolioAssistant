// Cuenta los tokens (o200k_base, el tokenizador de la familia GPT-4o/5) de
// los bloques del prefijo fijo de Porty. gpt-6-luna puede tokenizar un poco
// distinto: las proporciones valen, los absolutos son aproximados.
//
//   PROMPT_BLOCKS_DIR=/tmp/porty-blocks flutter test test/features/assistant/catalog/prompt_budget_test.dart
//   cd supabase/functions && deno run -A scripts/prompt_tokens.ts /tmp/porty-blocks
//
// Imprime tokens y caracteres por token de cada bloque: con eso se
// actualizan los presupuestos y las proporciones de `prompt_budget_test.dart`.
import { encode } from "npm:gpt-tokenizer@2.9.0/encoding/o200k_base";

const dir = Deno.args[0];
if (!dir) throw new Error("uso: prompt_tokens.ts <carpeta con los bloques>");

let total = 0;
for (const name of ["rules", "schemas", "genui", "tools"]) {
  const text = await Deno.readTextFile(`${dir}/${name}.txt`);
  const tokens = encode(text).length;
  total += tokens;
  console.log(
    `${name.padEnd(8)} ${String(tokens).padStart(6)} tokens  ` +
      `${String(text.length).padStart(7)} caracteres  ` +
      `${(text.length / tokens).toFixed(2)} car/token`,
  );
}
console.log(`${"total".padEnd(8)} ${String(total).padStart(6)} tokens`);

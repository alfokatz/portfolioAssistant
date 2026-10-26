# Tests de Supabase

## Edge functions (Deno)

- Ubicación: `supabase/functions/tests/<name>_test.ts`; helpers en `helpers.ts`, `etoro_fakes.ts`.
- Correr desde `supabase/functions`:
  ```bash
  deno task test                                        # todo: deno test --allow-net --allow-env --allow-read tests/
  deno test --allow-env tests/binance_sync_test.ts      # uno
  ```
- Estilo: `jsr:@std/assert@1`, nombres en español (`Deno.test("sin JWT → 401", ...)`), y se llama directo al handler con dependencias falsas: `handle(req, deps(fakeFetch(...).fetch, env))`.
- Los tests que usan `createUser` / `db` de `helpers.ts` necesitan el stack local (`supabase start`); toman `API_URL`/`SUPABASE_URL`, `SERVICE_ROLE_KEY`, `ANON_KEY` del entorno (`supabase status -o env`). Los "puros" corren sin stack. Si no hay stack levantado, decirlo en vez de reportar los rojos como fallas del cambio.

## SQL

- `supabase/tests/<x>_db_test.sql`: cada uno corre en una transacción con rollback e imprime `<X>_DB_TEST_OK`.
- `psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/watchlist_db_test.sql`
- Cubrir RLS (otro usuario no ve filas), límites por plan (trigger lanza el error tipado) y RPCs.

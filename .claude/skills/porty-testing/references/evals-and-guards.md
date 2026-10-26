# Evals pagas y tests guardianes

## Evals del asistente (`test/evals/assistant_tool_evals_test.dart`)

**Cuestan plata. Preguntar antes**, con plan de corridas y costo (referencia: corrida completa ≈ US$0,15–0,30; informe semanal ≈ US$0,004 por caso). Agrupar lo posible en una sola corrida.

- Skip por defecto: `RUN_ASSISTANT_EVALS=1` las activa.
- Van por el proxy `ai-chat`: por defecto `http://127.0.0.1:54321/functions/v1/ai-chat` (`supabase functions serve` local). Requiere `EVAL_PROXY_JWT` (falla si falta). Cada corrida completa necesita su propio usuario de eval (100 consultas/día).
- Opciones: `EVAL_ONLY=id1,id2` (subconjunto, preferido), `EVAL_DEBUG=1`, `EVAL_PRINT_TEXT=1`, `ASSISTANT_EVALS_REPORT=<archivo.json>`, `EVAL_REAL_DATA=1` (datos reales en vez de fakes), `EVAL_CASE_DELAY_S`, `EVAL_DUMP_DIR`.
- Runbook: `docs/runbooks/ai-proxy-cutover.md`.
- Errores de proceso que ya costaron plata: editar `handler.ts` con `functions serve` corriendo, timeouts del test, límites de CPU del serve local. Reiniciar `functions serve` antes de una corrida larga y no tocar archivos de funciones mientras corre.
- No son determinísticas: un caso que falla una vez se compara contra la versión anterior antes de llamarlo regresión.

## Evals del informe semanal (`test/evals/weekly_report_evals_test.dart`)

`RUN_WEEKLY_REPORT_EVALS=1` + `EVAL_REPORT_USERS=<json>` (generado con `cd supabase/functions && deno run -A scripts/eval_report_users.ts 14`). Modelo `EVAL_MODEL` (default `gpt-6-luna`). Salida en `EVAL_REPORT_OUT` (default `build/weekly_report_evals.json`).

## Guardianes

| Test | Invariante | Cómo se arregla |
|---|---|---|
| `test/security/system_prompt_allowlist_test.dart` | El sha256 del system prompt del chat está en `supabase/functions/ai-chat/allowed_system_prompts.json`; el del informe en `allowed_report_prompts.json` (y no en el del chat); el prompt es determinístico | `UPDATE_PROMPT_ALLOWLIST=1 flutter test test/security/system_prompt_allowlist_test.dart` (agrega, no borra). Si falla por determinismo: sacaste una fecha o dato del usuario al prompt → moverlo al `PORTFOLIO_BRIEF` o al resultado de una tool |
| `test/security/no_secrets_in_app_test.dart` | Ni `lib/` ni assets contienen nombres de keys, `sk-…`, `sb_secret_…`, `api.openai.com`, `finnhub.io` | Pasar la llamada por edge function |
| `test/branding/no_old_app_name_test.dart` | Sin "PortfolioAI"/"Portfolio Assistant" en traducciones, manifests ni strings; display name `Porty` | Renombrar el texto |
| `test/features/assistant/catalog/assistant_catalog_test.dart` | Cantidad de widgets, IDs `[W:…]` existentes, tamaño del prompt | Actualizar el número esperado si agregaste una card a propósito |
| `test/features/assistant/catalog/prompt_budget_test.dart` | Presupuesto de tokens del prompt | Recortar; `PROMPT_BLOCKS_DIR=<dir>` vuelca los bloques para medir con `supabase/functions/scripts/prompt_tokens.ts` |
| `test/features/assistant/tools/assistant_tools_test.dart` | Orden fijo de tools | Agregar la tool nueva al final de la lista esperada |

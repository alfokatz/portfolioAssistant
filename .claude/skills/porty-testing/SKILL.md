---
name: porty-testing
description: Cómo escribir y correr tests en Porty (Flutter + Supabase) - dónde va cada test, fakes escritos a mano sin mocktail, overrides de Riverpod, widget tests con tema y traducciones, screenshots por variable de entorno, evals pagas del asistente, tests de seguridad y tests Deno/SQL de Supabase. Usar al agregar o arreglar tests, al verificar un cambio antes de darlo por terminado, o cuando un test de test/security, test/branding o del catálogo falle.
---

# Testing en Porty

## Cómo correr

```bash
flutter test test/features/goals                     # por carpeta: lo normal mientras trabajás
flutter test test/features/goals/goals_screen_test.dart
flutter test                                         # suite completa (screenshots y evals se saltean solas)
flutter analyze
cd supabase/functions && deno test --allow-net --allow-env --allow-read tests/<name>_test.ts
```

- Correr desde la raíz del repo (los fixtures se leen con `File('test/...')`).
- No hay CI, ni `dart_test.yaml`, ni tags: `--tags` no hace nada.
- La suite completa está en verde: cualquier rojo hay que explicarlo.

## Dónde va el test

`test/` espeja `lib/` (con el typo `infraestructure`):

| Código en | Test en |
|---|---|
| `lib/features/<f>/...` | `test/features/<f>/...` |
| `lib/domain/...` | `test/domain/...` |
| `lib/infraestructure/...` | `test/infraestructure/...` |
| `lib/presentation/...` | `test/presentation/...` |
| `lib/config/supabase/...` | `test/config/supabase/...` |
| Capturas para revisar a ojo | `test/screenshots/<f>_screenshots_test.dart` |
| Modelo real (pago) | `test/evals/` |
| `supabase/functions/<fn>/` | `supabase/functions/tests/<fn>_test.ts` |
| SQL / RLS / triggers | `supabase/tests/<x>_db_test.sql` |

Archivos `<sujeto>_test.dart`. Helpers compartidos sin sufijo `_test` (ej. `test/features/assistant/fakes/assistant_fakes.dart`, `test/helpers/genui_test_helpers.dart`).

## Reglas

1. **Fakes a mano, sin mocktail ni mockito** (no están en el proyecto). Ver [references/fakes-and-overrides.md](references/fakes-and-overrides.md).
2. **Riverpod**: `ProviderContainer(overrides: [...])` en unit tests (con `addTearDown(container.dispose)`); `ProviderScope(overrides: ...)` en widget tests.
3. **Tema real** de la app en widget tests: `ProviderContainer().read(themeDataLightProvider)` / `themeDataDarkProvider`. Probar claro **y** oscuro en UI nueva.
4. **Traducciones**: sin cargar, `.tr()` devuelve la key → buscar por key. Para ver el texto real, cargar `es-ES.json` (ver [references/widget-tests.md](references/widget-tests.md)).
5. **Sin red real** en tests normales: `MockClient` de `package:http/testing.dart`, Dio con interceptor, Supabase con `httpClient: MockClient`.
6. **Nombres**: `group` con la clase o método (`group('GoalProgress')`); descripciones en inglés tipo oración ('behind plan: Porty is concerned'); comentarios en español. Cabecera del archivo: un comentario en español que diga qué cubre y cómo correrlo si necesita env.
7. **Tiempo**: los loaders aparecen a los 300 ms y quedan 400 ms mínimo; pumpear pasado eso para verlos o que desaparezcan. Con genui no esperar `Future.delayed` reales en `testWidgets` (fake async): usar `tester.pump` / `tester.runAsync`.
8. **Nunca `dart format test/`**: solo los archivos que creaste o tocaste.

## Qué testear según el cambio

| Cambio | Mínimo |
|---|---|
| Entidad / cálculo | unit test puro con casos borde |
| Repositorio | parseo + errores tipados con HTTP/Supabase falso |
| Notifier | estados `loaded` / `loadFailed` / acciones con `ProviderContainer` |
| Pantalla o widget | widget test: render, estados vacío/carga/error, interacción, claro y oscuro, ancho de iPhone SE (375) |
| UI visible nueva | además, screenshot test y **mirar las PNG** ([references/screenshots.md](references/screenshots.md)) |
| Tool o card del chat | ver skill **porty-assistant** + [references/evals-and-guards.md](references/evals-and-guards.md) |
| Edge function / SQL | [references/supabase-tests.md](references/supabase-tests.md) |

## Tests guardianes (si fallan, no es flaky)

- `test/security/system_prompt_allowlist_test.dart`: cambiaste prompt o catálogo → `UPDATE_PROMPT_ALLOWLIST=1 flutter test test/security/system_prompt_allowlist_test.dart` y avisar que hay que desplegar `ai-chat`.
- `test/security/no_secrets_in_app_test.dart`: hay una key, `sk-...`, `api.openai.com` o `finnhub.io` en `lib/` o assets. Sacarla; va por edge function.
- `test/branding/no_old_app_name_test.dart`: apareció "PortfolioAI"/"Portfolio Assistant". La app es Porty.
- `assistant_catalog_test.dart` / `prompt_budget_test.dart` / orden en `assistant_tools_test.dart`: cuenta de widgets, tamaño del prompt, orden fijo de tools.

Detalle en [references/evals-and-guards.md](references/evals-and-guards.md).

## Evals: preguntar antes

`RUN_ASSISTANT_EVALS=1` y `RUN_WEEKLY_REPORT_EVALS=1` llaman al modelo real y **cuestan plata**. Nunca exportarlas sin OK explícito del usuario, diciendo cuántas corridas y el costo estimado.

## Antes de decir "listo"

```
- [ ] Tests nuevos/actualizados para lo que cambió
- [ ] flutter test <carpetas tocadas> en verde (o rojo explicado)
- [ ] Si tocó UI: screenshots generadas y revisadas, claro/oscuro, SE/Pro
- [ ] Si tocó prompt/catálogo: test de allowlist en verde
- [ ] flutter analyze sin warnings nuevos
- [ ] Reportar al usuario qué se corrió y el resultado real (con salida si algo falló)
```

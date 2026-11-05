---
name: porty-architecture
description: Mapa de arquitectura de la app Flutter Porty (portfolio_assistant) - dónde va cada archivo, cómo se declaran providers Riverpod, rutas go_router, repositorios Supabase, edge functions, migraciones, traducciones y flags. Usar antes de crear o mover código en lib/ o supabase/, al agregar una feature, pantalla, provider, ruta, repositorio, tabla, edge function o texto traducible, o cuando haya duda de en qué capa va algo.
---

# Arquitectura de Porty

App Flutter (paquete `portfolio_assistant`) + backend Supabase (Postgres, edge functions en Deno). Si un doc dice algo distinto al código, **manda el código**.

## Decisión 1: ¿dónde va el código nuevo?

| Qué estás haciendo | Dónde |
|---|---|
| Capacidad de producto nueva (pantalla + datos) | `lib/features/<feature>/` ← **patrón preferido** |
| Algo del chat de Porty (tools, widgets del chat, prompt) | `lib/features/assistant/` → usar la skill **porty-assistant** |
| Motor genérico LLM/GenUI (sin saber de negocio) | `lib/features/genui_core/` |
| Extender el núcleo de posiciones, cotizaciones o suscripción | capas clásicas `lib/domain/` + `lib/infraestructure/` |
| Widget reutilizable entre features | `lib/presentation/shared/widgets/` |
| Tema, colores, dimensiones | `lib/presentation/base/theme/` |
| Router, Supabase client, HTTP | `lib/config/` |
| Planes y límites (free/premium/gold) | `lib/domain/subscription/plan_matrix.dart` |
| Tabla, RLS, RPC, flag | migración **nueva** en `supabase/migrations/` |
| Lógica de servidor / proxy de una API | `supabase/functions/<kebab-name>/` |

No crear código nuevo en `lib/presentation/flows/` (pantallas legacy) salvo que estés modificando esa pantalla.

## Estructura de una feature

```
lib/features/<feature>/
  data/<feature>_repository.dart   # habla con Supabase/edge; excepciones tipadas; provider al final
  domain/<entidad>.dart            # clases inmutables a mano: fromRow, toJson, copyWith
  providers/<feature>_provider.dart# StateNotifier + clase State
  view/<feature>_screen.dart       # pantallas (widgets privados _X en el mismo archivo)
  view/widgets/                    # widgets de la feature
  nav/<feature>_router.dart        # XxxRouter con routeName/path/getRoute()
```

Ejemplos reales para copiar: `lib/features/goals/`, `lib/features/binance/`, `lib/features/allocation/`. Detalle de cada pieza con código: [references/feature-anatomy.md](references/feature-anatomy.md).

## Reglas que no se negocian

1. **Riverpod a mano**: `hooks_riverpod` con `StateNotifierProvider` / `Provider` / `FutureProvider` declarados como `final xxxProvider` top-level. Nada de `@riverpod`, `Notifier`, `AsyncNotifier` ni codegen.
2. **Modelos a mano**: sin freezed ni json_serializable (están en pubspec pero no se usan). `build_runner` no es parte del flujo.
3. **Imports siempre `package:portfolio_assistant/...`**, nunca relativos.
4. **Navegación por nombre**: `context.pushNamed(XRouter.routeName)` / `goNamed`. Nunca `context.push('/path')`. Registrar el router en `lib/config/navigation/app_router.dart`.
5. **Planes por capacidad**: preguntar `SubscriptionPolicy.allows(tier, PlanFeature.x)`; nunca `if (tier == SubscriptionTier.gold)`. Una capacidad paga nueva entra primero en `PlanMatrix`.
6. **Sin secretos en la app**: OpenAI, Finnhub y Yahoo van por edge functions (`ai-chat`, `finnhub`, `yahoo`). En el cliente solo viven `SUPABASE_URL` y la anon key. Lo vigila `test/security/no_secrets_in_app_test.dart`.
7. **Edge functions con Dio** vía `PortyEdgeClient` (`lib/infraestructure/data_sources/porty_edge_client.dart`) o un cliente dedicado; nunca `supabase.functions.invoke`.
8. **Migraciones: nunca editar una existente**, aunque parezca que no se subió (el usuario hace `db push` sin avisar). Todo cambio va en un archivo nuevo, idempotente. Ver [references/backend.md](references/backend.md).
9. **Textos de UI traducibles** en `assets/translations/es-ES.json` **y** `en-US.json` (las dos). Ver [references/i18n.md](references/i18n.md).
10. **Nada de listas fijas de tickers** (ticker→sector, candidatos por perfil). Porty habla de cualquier ticker; los números salen de datos reales. Si falta un dato: `null` / "Sin clasificar", nunca adivinar.
11. **Errores**: los repositorios de features lanzan fallas tipadas (sealed `XxxFailure` o `XxxException(type)`) y el notifier las convierte en flags del estado (`loaded`, `loadFailed`). Mensajes al usuario con `ref.read(alertProvider.notifier).showError(...)` (se ve como `PortyToast`). No construir sobre `presentation/base/content_state/` (legacy, sin uso).

## Nombres

- Archivos `snake_case.dart`. Sufijos: `_screen`, `_router`, `_nav` (eventos de navegación), `_provider`, `_repository`, `_client`, `_tools`, `_widgets`, `_impl` (solo capas clásicas).
- Typos históricos que **no se corrigen** (rompería imports): `infraestructure`, `environmet_manager`, `color_extesion.dart`, `refesh_token_interceptor.dart`.
- Helpers solo estáticos: `abstract final class`.
- Comentarios y doc comments (`///`) en español rioplatense; prompts y descripciones de tools del LLM en inglés.
- Planes y specs: `docs/superpowers/{plans,specs,research}/YYYY-MM-DD-<tema>.md`; procedimientos operativos: `docs/runbooks/`.

## Trampas conocidas

- `lib/presentation/base/theme/color_extesion.dart` tiene **otro** `CustomColors` legacy sin uso. El bueno es `theme_extension.dart` (`context.customColors`).
- Hive está en el código pero es legacy: `positionsBoxProvider` lanza si se usa. Las posiciones viven en Supabase; las preferencias locales en SharedPreferences.

## Higiene de git y formato (reglas del usuario)

- **Nunca `git stash`** (push ni pop): hay un stash viejo que un `pop` aplicaría. Para comparar contra el original, copiar archivos al scratchpad o usar `git worktree`.
- **Nunca `dart format` sobre carpetas** (`lib`, `test`) ni ajenas: solo los archivos que creaste o tocaste, listados uno por uno.
- `flutter analyze` sin warnings nuevos antes de dar algo por terminado.

## Checklist al terminar un cambio

- [ ] El código está en la carpeta que indica la tabla de arriba
- [ ] Providers, modelos y rutas siguen el estilo a mano de las reglas 1–4
- [ ] Textos nuevos en `es-ES.json` y `en-US.json`
- [ ] Si tocaste esquema: migración nueva, no editada
- [ ] Si tocaste prompt o catálogo del chat: hash del allowlist regenerado (skill **porty-assistant**)
- [ ] Tests según la skill **porty-testing**; UI según la skill **porty-ui-design**
- [ ] `flutter analyze` limpio en lo tocado

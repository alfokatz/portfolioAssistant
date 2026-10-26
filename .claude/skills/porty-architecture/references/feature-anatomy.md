# Anatomía de una feature (con código)

Plantillas extraídas de `lib/features/goals/`, `lib/features/binance/` y `lib/features/allocation/`. Antes de escribir, abrir el archivo equivalente de una de esas features y copiar su forma.

## Contenido
- Repositorio (`data/`)
- Entidad (`domain/`)
- Provider (`providers/`)
- Pantalla (`view/`)
- Router (`nav/`)
- Capas clásicas (cuándo y cómo)
- Feature flags y entornos

## Repositorio (`data/`)

- Recibe el cliente como closure para que los tests corran sin Supabase:
  ```dart
  class GoalsRepository {
    GoalsRepository({required SupabaseClient? Function() client}) : _client = client;
    ...
  }

  final goalsRepositoryProvider = Provider<GoalsRepository>((ref) => GoalsRepository(
        client: () {
          try { return ref.read(supabaseClientProvider); } catch (_) { return null; }
        },
      ));
  ```
- Chequea `client.auth.currentUser`; usa `.from('tabla').select('col1, col2')` con columnas explícitas; atrapa `PostgrestException` y la convierte en una falla tipada (sealed `GoalsFailure` o `XxxException(type)`).
- Edge functions: `PortyEdgeClient` → `EdgeResponse` (`planRequired`, `errorType`). Ejemplo: `lib/features/binance/data/binance_repository.dart`.
- Sin interfaz abstracta ni use case: eso es solo de las capas clásicas.

## Entidad (`domain/`)

Clase inmutable con constructor `const`, `fromRow(Map<String, dynamic>)`, `toJson()`, `copyWith`. Enums con `storageValue` + `static fromStorage(String?)`. Ejemplo: `lib/features/goals/domain/user_goal.dart`, `lib/features/allocation/domain/allocation_plan.dart`.

## Provider (`providers/`)

```dart
class GoalsState {
  const GoalsState({this.goals = const [], this.loaded = false, this.loadFailed = false});
  ...
  GoalsState copyWith({...});
}

class GoalsNotifier extends StateNotifier<GoalsState> {
  GoalsNotifier(this._repo, {required this.holdings}) : super(const GoalsState());
  Future<void> load() async {
    try { ... state = state.copyWith(goals: list, loaded: true); }
    on GoalsFailure catch (e) { debugPrint('[Goals] $e'); state = state.copyWith(loadFailed: true); }
  }
}

final goalsProvider = StateNotifierProvider<GoalsNotifier, GoalsState>(
  (ref) => GoalsNotifier(ref.watch(goalsRepositoryProvider), holdings: () => ref.read(goalHoldingsProvider)),
);
```

- Dependencias por constructor (closures cuando hace falta leer tarde).
- Derivados con `Provider` aparte (ej. `allocationDriftProvider`).
- Features pueden importar providers de otras features y del núcleo (`homeProvider`, `quoteRepositoryProvider`).

## Pantalla (`view/`)

- `ConsumerStatefulWidget` es lo más común. Si la pantalla necesita los listeners globales de alertas/navegación, `StatefulHookConsumerWidget` + `extends BaseStatefulWidget<T>` con `buildView()` (ej. `goals_screen.dart`). Tabs del shell: `subscribesToGlobalEvents => false`.
- Carga inicial en `initState` con `runAfterPostFrameCallback(() => ref.read(xProvider.notifier).load())`.
- Widgets privados `_Nombre` en el mismo archivo; los compartidos de la feature en `view/widgets/`.
- Estilo visual: skill **porty-ui-design**.

## Router (`nav/`)

```dart
class BinanceRouter {
  static const routeName = 'Binance';   // PascalCase
  static const path = '/binance';       // minúscula
  static GoRoute getRoute() => GoRoute(
        name: routeName,
        path: path,
        pageBuilder: (context, state) => MaterialPage<void>(key: state.pageKey, name: routeName, child: const BinanceScreen()),
      );
}
```

Registrar en `routes:` (o en una rama del `StatefulShellRoute`) de `lib/config/navigation/app_router.dart`. Helpers opcionales tipo `GoalsRouter.openDetail(context, id)`. Desde un provider legacy se emite un `NavigationEvent` por `navigationProvider` (archivos `*_nav.dart`).

## Capas clásicas (solo para extender el núcleo)

- `lib/domain/entities/`, `repositories/` (interfaces), `use_cases/` (`XxxUseCase extends BaseUseCase<T, Params>` → `Either<HttpError, T>`, provider en el mismo archivo).
- `lib/infraestructure/repositories/*_impl.dart` con el provider al final; `data_sources/` con los clientes HTTP y Supabase.
- `lib/presentation/flows/<flow>/{ui,providers,states,nav}` usa `BaseStateNotifier<S, A>` con acciones selladas y `reducer()`. Notar: flows usan `ui/`, features usan `view/`.

## Feature flags y entornos

- Flavors: `flutter run --dart-define=FLAVOR=development|staging|production` carga `assets/env/.env.<flavor>`. Leer con `dotenv.maybeGet(...)` dentro de try/catch (los tests corren sin `.env`).
- Flags remotos: tabla `public.app_config` (`key text`, `value jsonb`, lectura pública). Se siembran con `insert ... on conflict do nothing` en una migración nueva. Ejemplos: `weekly_report` `{"enabled":bool}`, `porty_streaming` `{"percent","users"}` (`lib/features/assistant/data/porty_streaming_config.dart`), `min_supported_build`. Decidir y documentar si el flag falla abierto o cerrado.

# Fakes y overrides

## Contenido
- Cuatro estilos de fake
- HTTP, Dio y Supabase falsos
- SharedPreferences
- Riverpod
- Fakes compartidos del asistente

## Cuatro estilos de fake (elegir el más simple que alcance)

1. **`implements` la interfaz** y registrar llamadas:
   ```dart
   class CountingQuoteRepository implements QuoteRepository {
     final priceCalls = <String>[];
     @override
     Future<Either<HttpError, double>> getPrice(String t) async { priceCalls.add(t); return const Right(150); }
   }
   ```
2. **Interfaz grande**: `implements` + `noSuchMethod` para lo que no se usa:
   ```dart
   class _FakeAuthService implements SupabaseAuthService {
     ...
     @override
     dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
   }
   ```
3. **Subclase del repositorio real con cliente nulo** (repos de features):
   ```dart
   class _Repo extends GoalsRepository {
     _Repo(this.goals) : super(client: () => null);
     final List<UserGoal> goals;
     @override
     Future<List<UserGoal>> list() async => goals;
   }
   ```
4. **Fakes privados** chicos arriba del archivo: `_Subscription(tier)`, `_NoBrowser()`, `_LoadedHome(ref)`.

## HTTP, Dio y Supabase

- `http`: `MockClient((request) async => http.Response(body, 200))` de `package:http/testing.dart`. Ej.: `test/features/genui_core/ai_proxy_client_test.dart`.
- Dio: `Dio()..interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.resolve(Response(requestOptions: o, data: ..., statusCode: 200))))`. Ej.: `test/infraestructure/repositories/finnhub_company_news_repository_impl_test.dart`.
- Supabase real con HTTP falso (`test/config/supabase/supabase_auth_service_test.dart`):
  ```dart
  client = SupabaseClient('https://project.supabase.co', 'anon-key',
      authOptions: AuthClientOptions(autoRefreshToken: false, pkceAsyncStorage: pkce),
      httpClient: MockClient((request) async { requests.add(request); return http.Response('[]', 200); }));
  tearDown(() => client.dispose());
  ```
  En capas superiores es más simple overridear el provider (`supabaseAuthServiceProvider.overrideWithValue(fake)`).

## SharedPreferences

```dart
SharedPreferences.setMockInitialValues({'key': 'value'});
final prefs = await SharedPreferences.getInstance();
// overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]
```

## Riverpod

```dart
final container = ProviderContainer(overrides: [
  homeProvider.overrideWith((ref) => _Home(ref)),
  goalsRepositoryProvider.overrideWithValue(_Repo(goals)),
  portyHapticsServiceProvider.overrideWithValue(
      PortyHapticsService(enabled: true, performer: (p) async => haptics.add(p))),
]);
addTearDown(container.dispose);
```

- Widget test que necesita leer el container después: `UncontrolledProviderScope(container: container, child: ...)`.
- Ejemplo completo: `test/features/assistant/providers/assistant_actions_test.dart`.

## Fakes compartidos del asistente

`test/features/assistant/fakes/assistant_fakes.dart`: `CountingQuoteRepository`, `FakeSymbolSearchRepository`, `FakeCompanyNewsRepository`, `FakePreferences`, `FakeYahooProxy`, `FakeWebSearch`, `ScriptedOpenAi` (un `MockClient` que devuelve respuestas guionadas) y los builders `toolCallsReply`, `textReply`, `a2uiAnswer`. Reusar antes de escribir uno nuevo; si uno nuevo sirve a más de un test, agregarlo ahí.

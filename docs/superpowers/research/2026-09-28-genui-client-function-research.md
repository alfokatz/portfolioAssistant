# genui `ClientFunction` como mecanismo de tool calling: investigación

**Fecha:** 2026-09-28 · **Alcance:** puntual; no se tocó código de producción.
**Contexto:** [2026-09-28-unified-assistant-cutover.md](../plans/2026-09-28-unified-assistant-cutover.md). Queremos reemplazar la capa de heurísticas (keywords/regex que pre-fetchea datos) por tool calling decidido por el modelo.

## Veredicto

**No. `ClientFunction` no es tool calling y no sirve para nuestro caso.** Es una función del *lenguaje de expresiones de A2UI*: el modelo la referencia **dentro del JSON de UI** que emite (`{"call": "...", "args": {...}}` en un prop de un widget), y el cliente la evalúa **al renderizar ese widget**. El resultado va al widget, **nunca vuelve al modelo**. No hay loop, ni round-trip, ni encadenamiento con razonamiento. El modelo no puede ver un P/E y después decidir qué widget usar.

genui 0.10.x no trae ningún mecanismo de tool calling con el LLM. Su propio ejemplo oficial resuelve las tools **fuera** de genui, con un paquete de terceros.

**Recomendación:** implementar el loop de tool calling nosotros, en la capa que habla con OpenAI (`openai_genui_service.dart`), usando `tools`/`tool_calls` de la Chat Completions API. genui sigue siendo solo el renderer: recibe el texto A2UI final, como hoy. Este diseño **no depende de subir genui**. El upgrade a 0.10.3 es chico (ver abajo) y se puede hacer por separado, o no hacerlo.

Una premisa del brief era incorrecta: `ClientFunction` **no apareció en 0.9.0**. Ya existe en 0.8.0, que es la que usamos. Su API es idéntica byte a byte entre 0.8.0 y 0.10.3 (verificado con `diff`). La 0.8.0, además, *eliminó* del core los eventos `ToolStartEvent`/`ToolEndEvent` (CHANGELOG 0.8.0, "Internal").

## 1. Qué es `ClientFunction` (código fuente leído: genui 0.10.3, pub cache)

`lib/src/model/client_function.dart`:

```dart
abstract interface class ClientFunction {
  String get name;            // "as used in expressions (e.g. 'stringFormat')"
  String get description;
  Schema get argumentSchema;
  ClientFunctionReturnType get returnType => ClientFunctionReturnType.any;
  Stream<Object?> execute(JsonMap args, ExecutionContext context);
}
```

- **Quién la invoca:** `DataContext._evaluateFunctionCall` (`model/data_model.dart`) y `ExpressionParser.evaluateFunctionCall` (`functions/format_string.dart`). Los dos se disparan cuando un widget resuelve un valor dinámico `{"call": ...}` o una interpolación `${fn(...)}`. `ExecutionContext` le da acceso al *data model de la surface*, no a la conversación.
- **Qué recibe el modelo:** `PromptBuilder._generateCatalogSchema` (`facade/prompt_builder.dart`) serializa las funciones del catálogo en la sección `CATALOG SCHEMA` del system prompt, como `functions.<name> = {description, parameters, returnType}`. **No** las emite como `tools` de la API. El mismo builder agrega por defecto *"You do not have the ability to use function calls for UI generation."* (`TechnicalPossibilities`) y existe `PromptFragments.uiGenerationRestriction`: *"Do not use tools or function calls for UI generation. Use JSON text blocks."*
- **Dónde puede aparecer en el protocolo:** `FunctionCall` en `common_types.json` (embebido en `primitives/embedded_schemas.g.dart`) como `DynamicValue` de un prop, o como acción `{"functionCall": ...}` de un botón (*"Executes a local client-side function"*).
- **Funciones que trae el paquete** (`catalog/basic_functions.dart`): `and`, `or`, `not`, `required`, `regex`, `length`, `numeric`, `email`, `openUrl`, `formatNumber`, `formatCurrency`, `formatDate`, `pluralize`. Son validaciones y formatters, coherente con el propósito.
- **Qué vuelve al modelo:** lo único que `Conversation` reenvía al LLM es `SurfaceController.onSubmit`, que publica eventos de usuario (botones) y errores de validación. El resultado de una `ClientFunction` no pasa por ahí.

### Probe descartable (compiló y pasó en genui 0.10.3, Flutter 3.47.5 / Dart 3.13.4)

```dart
class GetFundamentalsFunction implements ClientFunction {
  GetFundamentalsFunction(this.calls);
  final List<JsonMap> calls;
  @override String get name => 'getFundamentals';
  @override String get description => 'Returns the P/E ratio of a ticker.';
  @override Schema get argumentSchema =>
      S.object(properties: {'ticker': S.string()}, required: ['ticker']);
  @override ClientFunctionReturnType get returnType => ClientFunctionReturnType.string;
  @override
  Stream<Object?> execute(JsonMap args, ExecutionContext context) async* {
    calls.add(args);
    await Future<void>.delayed(Duration.zero); // async, como un fetch real
    yield '${args['ticker']} P/E: 28.4';
  }
}

// testWidgets:
final catalog = BasicCatalogItems.asCatalog()
    .copyWith(newFunctions: [GetFundamentalsFunction(calls)]);
final prompt = PromptBuilder.chat(catalog: catalog).systemPrompt().join('\n');
expect(prompt, contains('"getFundamentals"'));                 // va en el CATALOG SCHEMA
expect(prompt, contains('You do not have the ability to use function calls for UI generation.'));

final controller = SurfaceController(catalogs: [catalog]);
final submitted = <ChatMessage>[];
controller.onSubmit.listen(submitted.add);
await tester.runAsync(() async {             // la validación es async desde 0.10.0
  controller.handleMessage(core.A2uiMessage.fromJson({'version': 'v0.9',
      'createSurface': {'surfaceId': 's1', 'catalogId': basicCatalogId}}));
  controller.handleMessage(core.A2uiMessage.fromJson({'version': 'v0.9',
      'updateComponents': {'surfaceId': 's1', 'components': [
        {'id': 'root', 'component': 'Text',
         'text': {'call': 'getFundamentals', 'args': {'ticker': 'AAPL'},
                  'returnType': 'string'}}]}}));
  await Future<void>.delayed(const Duration(milliseconds: 200));
});
expect(calls, isEmpty);                       // no corre hasta que un widget la bindea
await tester.pumpWidget(MaterialApp(home: Scaffold(
    body: Surface(surfaceContext: controller.contextFor('s1')))));
await tester.pump(); await tester.pump(const Duration(milliseconds: 50));
expect(calls, [{'ticker': 'AAPL'}]);
expect(find.text('AAPL P/E: 28.4', findRichText: true), findsOneWidget);
expect(submitted, isEmpty);                   // nada volvió al modelo
```

Salida: `PROBE OK — calls=[{ticker: AAPL}] submittedToModel=0`.

Esto muestra el techo del mecanismo. Para que el modelo "use" el P/E, tendría que haber decidido *de antemano* qué widget renderizar y cablear la función a un prop. No puede razonar sobre el valor, compararlo, elegir otro widget ni pedir un segundo dato según el primero.

## 2. OpenAI vs Firebase/Gemini

- El core de genui ya no depende de ningún proveedor. `Transport` (`interfaces/transport.dart`) es una interfaz de 4 miembros (`incomingText`, `incomingMessages`, `sendRequest`, `dispose`), y `A2uiTransportAdapter` recibe chunks de texto de cualquier origen. Así funciona hoy nuestro `OpenAIGenUiService`. En 0.10.3 no existe ningún `ContentGenerator`.
- **No hay generador para OpenAI, y tampoco para Gemini**, que haga tool calling. El monorepo `flutter/genui` (clonado, HEAD `e1f3caa`, 2026-09-28, versión 0.10.4 sin publicar) tiene `genui`, `genai_primitives`, `genui_a2a`, `json_schema_builder` y `archive/`. Ninguno implementa un loop de tools contra un LLM.
- `genai_primitives` (dependencia transitiva) define `ToolPart` con `ToolPartKind.call/result` y `Parts.toolCalls`/`toolResults`. Son solo tipos de mensaje, sin lógica de ejecución.
- **El ejemplo oficial** `examples/simple_chat/lib/agent/ai_client.dart` hace tool calling con **`dartantic_ai`** (`dartantic.Agent.forProvider(..., tools: [dartantic.Tool(name: 'listClimbingLocations', onCall: ...)])`), y a genui le pasa solo el texto final (`result.output`). Es el patrón que recomiendo, pero con nuestro cliente OpenAI.

## 3. Upgrade 0.8.0 → 0.10.3: tamaño real

Lo medí en una **copia descartable del repo** (sin `.git` ni plataformas): subí `genui` a 0.10.3, corrí `flutter analyze` y los tests de `test/features/genui_core` + `test/features/assistant`, y comparé contra 0.8.0 en la misma copia.

Versiones publicadas en el rango: 0.8.0 → 0.9.0 → 0.9.2 (no existe 0.9.1 en pub.dev) → 0.10.0 → 0.10.1 → 0.10.2 → 0.10.3.

**Cambios necesarios (son tres, todos chicos):**

| # | Qué | Dónde | Detectado por |
|---|-----|-------|---------------|
| 1 | Subir `json_schema_builder: ^0.1.3` → `^0.1.7` | `pubspec.yaml` | **Error de compilación dentro de genui**: `Type 'SchemaRegistry' not found`. genui 0.10.3 declara `json_schema_builder: ^0.1.3`, pero usa `SchemaRegistry`, que 0.1.5 (la de nuestro lock) no exporta. `flutter analyze` **no** lo reporta; aparece recién al compilar tests o la app. Es un bug de constraint de genui. |
| 2 | `A2uiMessage` ahora viene de `package:a2ui_core` (0.10.0: *"GenUI message classes … are removed"*). Se arregla agregando `import 'package:a2ui_core/a2ui_core.dart' show A2uiMessage;` y `a2ui_core` como dependencia directa. | `lib/features/genui_core/utils/a2ui_controller_dispatch.dart:14` | `flutter analyze` (único error nuevo) |
| 3 | **Cambio silencioso de catalog ID.** `A2uiResponseNormalizer.defaultCatalogId` está hardcodeado a `https://a2ui.org/specification/v0_9/standard_catalog.json`, que era el `basicCatalogId` de 0.8.0. En 0.10.3, `basicCatalogId` = `…/v0_9/catalogs/basic/catalog.json` y el único alias es `…/v0_9/basic_catalog.json`, así que `standard_catalog.json` ya no matchea ningún catálogo y las surfaces no renderizan. Solución: usar la constante `basicCatalogId` del paquete en vez del literal, y actualizar los fixtures. | `lib/features/genui_core/utils/a2ui_response_normalizer.dart:6`, fixtures en `test/features/genui_core/a2ui_response_normalizer_test.dart` y `genui_pipeline_test.dart` | Tests: **6 regresiones** (todas de render de surface: `genui_pipeline_test` "surface builds in widget tree" y 5 de `PortfolioQaAssistantSurface` en `assistant_loading_animations_test`). Con el ID corregido pasan 14/14 en esos archivos. |

**Resultado de tests** (mismos directorios, misma copia):
- 0.8.0 (línea base): 5 fallos preexistentes, que **no son del upgrade**: `createFundamentalsEnricher` faltante en `unified_submit_e2e_test.dart:211`, `CTX-SHARED-1`, 2× "ticker without historical data", "buildSnapshotJson explore mode". Son los cambios staged a medio hacer del working tree.
- 0.10.3 sin fixes: esos 5 + las 6 regresiones del punto 3.
- 0.10.3 con los 3 fixes: **593 pasan / 5 fallan**, y los 5 son exactamente los preexistentes. **Cero regresiones.** Pero la corrida tardó **45 min**, contra ~3 min antes de aplicar los fixes (ver "Tests que no terminan" en riesgos).

**Lo que no rompe** (verificado con analyze + tests):
- Catálogo: todos los widgets de `AssistantCatalog` (`assistant_catalog.dart`), `PortfolioQaCatalog` y `UnifiedAssistantCatalog`, construidos con `BasicCatalogItems.asCatalog().copyWith(...)` y `CatalogItem` (59 usos) + `CatalogItemContext` (29): 0 errores. El CHANGELOG 0.10.0 lo confirma: *"The catalog-widget authoring API is unchanged"*.
- `openai_genui_service.dart`: `SurfaceController(catalogs:)`, `A2uiTransportAdapter(onSend:)`, `Conversation(controller:, transport:)`, `onSubmit`, `contextFor`: sin cambios.
- `genui_surface_ids.dart`: no importa genui. `a2ui_response_normalizer.dart`: no importa genui (solo el problema del ID del punto 3).
- `PromptBuilder.custom(...)` (en `assistant_openai_service.dart`): sigue siendo síncrono.

**El CHANGELOG no coincide con el código publicado.** 0.10.0 anuncia *"BREAKING: `PromptBuilder.chat`/`custom` → async `createChat`/`createCustom`"*, pero en 0.10.3 (y en `main`) no existe `createChat` y `chat()`/`custom()` siguen sync. Hay que leer el código, no el changelog.

**Cambios de comportamiento a tener en cuenta** (0.10.0; ninguno rompió tests nuestros):
- La validación de componentes pasó a ser **async** (`SurfaceController._validateComponents` con `SchemaRegistry`). En `testWidgets` hay que envolver `handleMessage` en `tester.runAsync`, o se bloquea (me pasó en el probe).
- Un `createSurface` duplicado para un id activo ahora es error.
- `DataModel` es más estricto con las escrituras.

## 4. Esbozo de la alternativa: tool loop propio en `OpenAIGenUiService`

Sin pseudo-API de genui: es la Chat Completions API de OpenAI, que ya usamos (`dart_openai`, y `dio` en `openai_raw_chat_client.dart`).

```
handleSend(userMessage):
  history += user
  loop (máx N iteraciones, p.ej. 4):
    resp = chat.completions(model, history, tools: [get_quote, get_fundamentals,
                                                    get_earnings_calendar, get_news],
                            tool_choice: auto)       // no-stream en rondas de tools
    if resp.tool_calls vacío: break
    history += assistant(tool_calls)
    for call in resp.tool_calls (en paralelo):
      result = registry[call.name](jsonDecode(call.arguments))   // Finnhub / Yahoo
      history += tool(tool_call_id: call.id, content: jsonEncode(result))
  // última ronda: el modelo ya tiene los datos y emite A2UI como hoy
  stream final → LlmJsonSanitizer → A2uiResponseNormalizer → A2uiControllerDispatch
```

- Cada tool es una clase nuestra (`name`, `description`, JSON schema de parámetros, `Future<Map> run(args)`) que envuelve los repos existentes (`FundamentalsEnricher`, quote repo, Finnhub earnings/news). Para los schemas se puede reusar `json_schema_builder`, que ya es dependencia. **No usar `ClientFunction`**: su contrato (`Stream`, `ExecutionContext` del data model) es para widgets, no para esto.
- La ronda final sigue siendo texto A2UI, así que se mantiene la advertencia actual de no usar `response_format: json_object`, y el system prompt de `PromptBuilder` no cambia. Ojo: ese prompt dice *"You do not have the ability to use tools for UI generation"*. Es correcto para la **UI**, pero conviene aclarar en un fragmento propio que las tools de datos sí están disponibles, para que el modelo no se confunda.
- Alternativa a evaluar en el diseño grande: `dartantic_ai` (lo usa el ejemplo oficial y tiene provider OpenAI) en vez de escribir el loop a mano. Agrega una dependencia y reemplaza `dart_openai` en este flujo, así que habría que medir el choque con `OpenAiRequestThrottle`, el timeout por intento y el retry de `handleSend`.

## Riesgos y obstáculos

- **SDK:** genui ≥0.8.0 ya exige Dart `>=3.10.0` y Flutter `>=3.35.7`. Nuestro `pubspec.yaml` dice `sdk: ^3.7.0`, pero el toolchain local es Dart 3.13.4 / Flutter 3.47.5, así que el piso real ya lo pone genui 0.8.0. El upgrade no cambia esto.
- **Dependencias transitivas:** `pub get` con 0.10.3 resolvió sin conflictos contra el resto del `pubspec.yaml`. Agrega `a2ui_core 0.1.1` y requiere `json_schema_builder ≥0.1.7` (ver fix 1). genui 0.10.3 también trae `audioplayers`, `video_player`, `flutter_markdown_plus` y `url_launcher`; estos ya estaban en 0.8.0.
- **Tests lentos o que no terminan:** con 0.10.3, el proceso `flutter_tester` del probe a veces no termina *después* de que el test pasa (0% CPU, requiere kill). La suite `genui_core` + `assistant` de la copia pasó de ~3 min a **45 min**. Además, flutter avisa que genui crea un `HttpClient` durante la validación async de componentes. Sospecho de esa validación (`SchemaRegistry` resolviendo `$ref`), pero no diagnostiqué la causa. **Es el bloqueante práctico del upgrade:** hay que investigarlo antes de mergear.
- **Changelog poco confiable** (ver `createChat`): cualquier plan de upgrade tiene que basarse en el código.
- `ClientFunction` puede seguir siendo útil para lo que sí hace: formatters o validaciones client-side en widgets (p.ej. `formatCurrency`). Eso es independiente de la migración a tools.

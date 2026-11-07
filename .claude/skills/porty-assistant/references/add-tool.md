# Agregar una tool de datos

Copiar este checklist y marcarlo:

```
- [ ] 1. Clase DataTool en el *_tools.dart del grupo correcto
- [ ] 2. Fetch de datos en features/assistant/data/<area>/ (sin LLM)
- [ ] 3. PlanFeature nuevo en PlanMatrix (si es paga) + ctx.gate
- [ ] 4. Agregada AL FINAL de AssistantToolset.build
- [ ] 4b. Asignada a un área en lib/features/assistant/areas/porty_areas.dart
         (con sus widgets); si su regla de respuesta o su card solo hacen
         falta con sus datos → DeferredSpec (viaja en area_spec con el
         prompt lean). El presupuesto del área no se sube sin pensarlo
- [ ] 5. Regla [W:…] o AnswerGuide si el modelo necesita guía
- [ ] 6. Grounding: _requires si alimenta un widget
- [ ] 7. Hash del allowlist regenerado
- [ ] 8. Tests: unit de la tool + test de orden + caso de eval (sin correrla)
```

## 1. La clase

Implementa `DataTool` (`lib/features/genui_core/tool_calling/data_tool.dart`):

```dart
// Ejemplo ilustrativo: get_insider_trades no existe.
class GetInsiderTradesTool implements DataTool {
  GetInsiderTradesTool(this.ctx);
  final AssistantToolContext ctx;

  @override
  String get name => 'get_insider_trades';           // estable: es parte del prefijo cacheado

  @override
  String get description =>                      // en inglés: cuándo usarla, cuándo NO, qué devuelve cada campo
      'Recent insider buys and sells for 1-3 tickers. Use when the user asks whether executives are buying or selling. '
      'Do not use for price moves. Returns per ticker: net_shares, last_trade_date, trades[].';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'tickers': {'type': 'array', 'items': {'type': 'string'}, 'minItems': 1, 'maxItems': 3},
        },
        'required': ['tickers'],
      };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final tickers = ToolArgs.tickers(args);               // validar todo con ToolArgs (string, number, date, strings)
    if (tickers.isEmpty) return ToolArgs.invalid();
    final locked = ctx.gate(PlanFeature.insiderTrades, tickers);
    if (locked != null) return locked;
    try {
      ...
      return {'status': 'ok', 'as_of': ..., 'items': ...};
    } catch (_) {
      return {'status': 'failed', 'as_of': ...};          // nunca lanzar
    }
  }
}
```

El grupo expone `abstract final class XTools { static const names = [...]; static List<DataTool> build(ctx) }`. Datos de otras features: a través del `ctx`, no importando repos sueltos dentro de la tool.

## 2. Orden

Agregar al **final** de `AssistantToolset.build`, sin reordenar: el orden es parte del caché de OpenAI y lo fija un test en `test/features/assistant/tools/assistant_tools_test.dart` (actualizarlo).

## 3. Guía de respuesta

Preferir `AnswerGuide.attach(result, guide)` (ver `PlanGuides` en `plan_tools.dart`) a sumar texto al system prompt. Si hace falta una regla de ruteo de widget, una línea en `assistant_prompt_rules.dart` con un `[W:ID]` nuevo; el test de contrato verifica que los IDs referenciados existan.

## 4. Tests

- Unit: `test/features/assistant/tools/<grupo>_tools_test.dart` con los fakes de `test/features/assistant/fakes/assistant_fakes.dart`. Cubrir: cada `status`, gating por tier (free/premium/gold), argumentos inválidos.
- Eval: agregar un caso en `test/evals/assistant_tool_evals_test.dart`. **No correrla** sin OK del usuario (cuesta).
- Allowlist: ver SKILL.md.

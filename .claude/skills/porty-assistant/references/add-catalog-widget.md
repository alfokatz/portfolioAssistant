# Agregar una card al chat (widget Qa* del catálogo)

Plantillas: commit `b9903ba` (QaEtfHoldings, completo) y `QaAllocationPlan` (`catalog/widgets/allocation_plan_widgets.dart` + `data/plan/allocation_plan_card_data.dart`, números inyectados por la app).

```
- [ ] 1. Widget en catalog/widgets/<dominio>_widgets.dart usando SOLO el kit
- [ ] 2. CatalogItem qaXItem en portfolio_qa_catalog.dart (dataSchema + exampleData)
- [ ] 3. Nombre en widgetNames e ítem en items de assistant_catalog.dart
- [ ] 4. _requires en AssistantGroundingCheck (widget → tools que lo respaldan)
- [ ] 5. Inyección de evidencia en AssistantAnswerReview si la app pone los números
- [ ] 6. Regla [W:…] en el prompt o AnswerGuide en la tool
- [ ] 7. Hash del allowlist regenerado
- [ ] 8. Tests: qa_<x>_test.dart + assistant_catalog_test.dart (cuenta de widgets, tamaño del prompt)
- [ ] 9. Screenshots claro/oscuro, SE y Pro, revisadas a ojo
```

## Reglas de la card

- Envolver en `QaCardShell` (da la entrada animada y los haptics). Título con `QaCardTitle`.
- Estilos solo de `QaText`, colores de `QaColors`, espacios de `QaSpace`, formato de `QaFormat`. **Ningún `TextStyle` suelto** ni `context.customColors` dentro del catálogo: si falta un estilo, se agrega al kit.
- Termina con `QaFollowUpBar` (seguimientos por `QaFollowUpScope`, no por eventos de genui).
- Bloque interno: `QaInset`, nunca una card dentro de la card. Separar secciones con `QaSection`; las filas no llevan divisores.
- Suba/baja solo con `QaDeltaChip`. Logos con `QaTickerAvatar` / `QaTickerHeader` (enriquecimiento visual del lado del cliente).
- Si el número lo puede poner la app, `dataSchema` no lo pide al modelo: `properties: {}` y se llena con la evidencia del turno.
- `widgetBuilder: (ctx) => guardedCatalogWidget(ctx, X.qaY)` para que un error caiga en `GenUiErrorCard` y no rompa el chat.
- `exampleData` real y completo: lo usan los tests (`pumpCatalogItemExample`) y las screenshots.

Diseño visual detallado: skill **porty-ui-design** → `references/genui-kit.md`.

## Tests

- `test/features/assistant/catalog/qa_<x>_test.dart`: render con `pumpCatalogItemExample` (`test/helpers/genui_test_helpers.dart`), estados vacío/locked, claro y oscuro.
- Actualizar `test/features/assistant/catalog/assistant_catalog_test.dart` (fija la cantidad de widgets y acota el prompt) y, si cambia el tamaño, `prompt_budget_test.dart`.
- Agregar el escenario a `test/screenshots/genui_catalog_screenshots_test.dart` y generar: `RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=<scratchpad>/shots flutter test test/screenshots/genui_catalog_screenshots_test.dart`. Mirar las PNG antes de decir que está listo.

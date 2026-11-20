# Screenshot tests

No son goldens: no comparan nada. Generan PNG para que una persona (o vos, leyéndolas con Read) revise el diseño. Se saltean salvo `RUN_SCREENSHOTS=1`.

## Correr

```bash
RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=<scratchpad>/shots flutter test test/screenshots/goals_screenshots_test.dart
```

Default de salida: `build/screenshots`. Después **abrir las PNG con Read** y revisarlas contra la checklist de la skill **porty-ui-design** antes de reportar.

## Cómo están armados (copiar de `test/screenshots/goals_screenshots_test.dart`)

- Gate: `final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';` y `testWidgets(id, ..., skip: !_enabled)`; `setUpAll` retorna temprano si está apagado.
- Dispositivos: `{'se': (Size(375, 667), 2.0), 'pro': (Size(402, 874), 3.0)}`, padding superior falso de 47.
- Recorre `Brightness.values` (claro y oscuro) × escenarios, con `platformBrightnessTestValue`.
- Captura: `RepaintBoundary(key:)` + `tester.runAsync(() => render.toImage(pixelRatio: dpr))` → `$_out/<id>.png`.
- `settle()`: bucle de `runAsync(delay 200 ms)` + `pump(2 s)`.
- `MaterialApp` con `GlobalMaterialLocalizations.delegates`, locale `es_ES`, `initializeDateFormatting('es_ES')`, `Intl.defaultLocale = 'es_ES'`, traducciones cargadas.
- Fuentes reales con `FontLoader`: `assets/fonts/PlusJakartaSans-{Regular,Medium,SemiBold,Bold}.ttf` registradas como `Plus Jakarta Sans`, y `MaterialIcons-Regular.otf` desde `$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/`.
- `PortyAvatar.ambientMotion = false`.

## Casos especiales

- Catálogo del chat: `test/screenshots/genui_catalog_screenshots_test.dart`.
- Informe semanal: lee `test/screenshots/weekly_report_samples.json`.
- `porty_splash_assets_test.dart` usa `RUN_SPLASH_ASSETS=1` y **sobrescribe** `assets/porty-avatar/splash/`; después va `dart run flutter_native_splash:create`, que reescribe `ios/Runner/Info.plist` → revertir ese archivo con `git checkout` (solo cambia `UIStatusBarHidden`). No correrlo salvo que el usuario lo pida.

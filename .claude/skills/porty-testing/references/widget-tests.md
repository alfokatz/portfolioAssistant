# Widget tests

Modelo a copiar: `test/features/goals/goal_detail_screen_test.dart`.

## Esqueleto

```dart
Future<void> pumpScreen(WidgetTester tester, {ThemeData? theme, Size size = const Size(390, 2200)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [goalsProvider.overrideWith((ref) => _Goals([goal]))],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? ProviderContainer().read(themeDataLightProvider),
      home: const GoalDetailScreen(goalId: 'g1'),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadSpanish); // solo si el test busca textos reales

  testWidgets('behind plan: Porty is concerned', (tester) async {
    await pumpScreen(tester);
    expect(find.text('...'), findsOneWidget);
  });

  testWidgets('dark theme renders without light-only colors', (tester) async {
    await pumpScreen(tester, theme: ProviderContainer().read(themeDataDarkProvider));
    ...
  });
}
```

## Traducciones

- Por defecto no se carga easy_localization: `.tr()` devuelve la key. Buscar con `find.text('goals_title')`.
- Para texto real o plurales (patrón de `goal_detail_screen_test.dart` y `porty_header_test.dart`):
  ```dart
  // ignore: implementation_imports
  import 'package:easy_localization/src/localization.dart';
  // ignore: implementation_imports
  import 'package:easy_localization/src/translations.dart';

  void loadSpanish() {
    Localization.load(const Locale('es', 'ES'),
        translations: Translations(jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())),
        ignorePluralRules: false);
  }
  ```

## Tamaños

- iPhone SE: `Size(375, 667)`; Pro: `Size(402, 874)`. Probar el más chico cuando hay filas con montos largos, teclado abierto o CTA al pie.
- Overflow de layout = test rojo (Flutter lanza). No taparlo con tamaños gigantes salvo para pantallas con scroll largo.

## Widgets del catálogo del chat

`test/helpers/genui_test_helpers.dart`:
- `pumpCatalogItemExample(tester, catalog, item, exampleIndex: 0)` arma la card desde su `exampleData` a 390×844 y verifica que no aparezca `GenUiErrorCard`.
- `genuiTestApp(child:)`, `genuiTestTheme()` (oscuro con `CustomColors.dark`), `loadGenuiFixture(name)` (lee `test/fixtures/genui/`), `dispatchNormalizedA2ui`.

## Animaciones y loaders

- `PortyAvatar.ambientMotion = false` en tests que hacen `pumpAndSettle` con Porty en pantalla (si no, nunca termina).
- Loaders: `await tester.pump(const Duration(milliseconds: 350))` para que aparezca; `+400 ms` para que pueda irse.
- Reduce motion: envolver con `MediaQuery(data: const MediaQueryData(disableAnimations: true), ...)` para verificar el camino sin animación.
- Haptics: overridear `portyHapticsServiceProvider` y afirmar sobre la lista registrada.

## Home real

Para montar la Home completa usar `HomeTestHarness` de `test/presentation/flows/home/home_loading_test.dart`.

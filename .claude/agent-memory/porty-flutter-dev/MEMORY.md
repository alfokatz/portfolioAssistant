# Memoria de porty-flutter-dev

- No hay Flutter en la máquina: bajar `flutter_linux_<ver>-stable.tar.xz` de storage.googleapis.com al scratchpad y usar su `bin` (pub get no toca pubspec.lock).
- Widget tests con precios: si el FutureProvider resuelve en el mismo `pump(500ms)` que el timer de 300 ms, `DelayedLoaderVisibility` muestra el skeleton; hacer `pump()` x2 antes del pump largo.
- `pumpWidget` de otro `ProviderScope` en el mismo test no reemplaza los `overrideWith`: un escenario por `testWidgets`.
- El tema ya pone `showDragHandle: true` en los bottom sheets: no dibujar otra manija.
- `dart format` en archivos legacy reformatea todo el archivo: copiar antes al scratchpad y revertir si mete ruido fuera de tus líneas. El hook bloquea `dart format` con variables o pipes: listar paths literales.
- Los sources del paywall deben cumplir `^[a-z][a-z0-9_]{2,59}$` (assert en `show`): usar `PaywallSource.snake` para nombres de enum.
- Una flow que cierra sesión desmonta la pantalla que la lanzó: usar `ProviderScope.containerOf(context)`, no `ref`; y `PortyLoader` se expande (Expanded): en una hoja/Column min hay que darle SizedBox con alto.
- `dart format --output=none` sobre una copia en /tmp NO sirve para saber si el original estaba formateado (distinta versión de lenguaje): correrlo en el lugar con `--output=none` y formatear solo los archivos que ya salen limpios.
- Tests que abren el paywall desde otras pantallas: spreadear `PaywallHarness().overrides` (test/features/subscription/paywall_test_harness.dart) y leer `h.events`; el teaser del informe semanal queda abajo, subir `tester.view.physicalSize` o el tap no pega.
- Cambiar `PlanMatrix` rompe tests de `test/features/assistant` (no son del flutter-dev): avisar a porty-assistant-dev en vez de tocarlos.
- El hook bloquea `dart format` si va en el mismo comando que `cd`/`sed`/`;`: un comando solo, paths absolutos literales.
- Widget nativo: workmanager iOS usa el `uniqueName` como id del BGTask (debe estar en BGTaskSchedulerPermittedIdentifiers) y registra el handler solo; el isolate de fondo no tiene easy_localization (textos del widget se leen del JSON con `WidgetTexts`).
- Con Xcode 27 `pod install` (y por ende `flutter build ios`) falla por objectVersion 70 del pbxproj: backup del pbxproj, `sed` a 60, `LANG=en_US.UTF-8 pod install`, restaurar el backup, y compilar con `xcodebuild -workspace Runner.xcworkspace -scheme Runner -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO` (no con flutter build, que vuelve a borrar Pods).
- Extensión iOS nueva = ciclo de build en Runner: mover "Embed Foundation Extensions" antes de "Thin Binary" en buildPhases. Los colorsets generan `Color.<nombre>`: no declarar extensiones con el mismo nombre.
- Android: estilos con punto (`PortyWidget.Total`) necesitan `parent=""`; `sed -i` en macOS pide `''`, y un `&&` cortado deja los heredocs escribiendo en el cwd equivocado.
- Widget nativo: `flutter build ios` puede fallar por Dart en edición del otro agente; compilar solo la extensión con `xcodebuild -workspace Runner.xcworkspace -scheme PortyWidgetExtension -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build` y chequear la decodificación con un swiftc scratch (stub de PortyEntry + SnapshotStore + PortyWidgetItems) contra test/fixtures/home_widget.
- Widget Android: sin SDK ni Maven (429) no hay forma de compilar Kotlin acá; el selector (PortyFeedPicker, solo org.json) se puede probar con un proyecto kotlin("jvm") en el scratchpad si Maven responde. Caras nuevas se buscan por getIdentifier (necesitan tools:keep en values/widget_keep.xml).

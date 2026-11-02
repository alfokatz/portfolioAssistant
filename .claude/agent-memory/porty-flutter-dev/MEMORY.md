# Memoria de porty-flutter-dev

- No hay Flutter en la máquina: bajar `flutter_linux_<ver>-stable.tar.xz` de storage.googleapis.com al scratchpad y usar su `bin` (pub get no toca pubspec.lock).
- Widget tests con precios: si el FutureProvider resuelve en el mismo `pump(500ms)` que el timer de 300 ms, `DelayedLoaderVisibility` muestra el skeleton; hacer `pump()` x2 antes del pump largo.
- `pumpWidget` de otro `ProviderScope` en el mismo test no reemplaza los `overrideWith`: un escenario por `testWidgets`.
- El tema ya pone `showDragHandle: true` en los bottom sheets: no dibujar otra manija.
- `dart format` en archivos legacy reformatea todo el archivo: copiar antes al scratchpad y revertir si mete ruido fuera de tus líneas. El hook bloquea `dart format` con variables o pipes: listar paths literales.
- Los sources del paywall deben cumplir `^[a-z][a-z0-9_]{2,59}$` (assert en `show`): usar `PaywallSource.snake` para nombres de enum.

// Migración de "Ocultar montos" a "Ocultar posiciones".
// Correr: flutter test test/features/home_widget/providers/widget_settings_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  group('readPositionsHidden', () {
    test('new key wins, then legacy, then false', () async {
      expect(WidgetPrefsKeys.readPositionsHidden(await _prefs({})), isFalse);
      expect(
        WidgetPrefsKeys.readPositionsHidden(
          await _prefs({WidgetPrefsKeys.legacyAmountsHidden: true}),
        ),
        isTrue,
      );
      expect(
        WidgetPrefsKeys.readPositionsHidden(
          await _prefs({
            WidgetPrefsKeys.positionsHidden: false,
            WidgetPrefsKeys.legacyAmountsHidden: true,
          }),
        ),
        isFalse,
      );
    });
  });

  group('WidgetPositionsHiddenNotifier migration', () {
    test('legacy true migrates to true and the old key is removed', () async {
      final prefs = await _prefs({WidgetPrefsKeys.legacyAmountsHidden: true});
      final n = WidgetPositionsHiddenNotifier(prefs);
      expect(n.state, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getBool(WidgetPrefsKeys.positionsHidden), isTrue);
      expect(prefs.containsKey(WidgetPrefsKeys.legacyAmountsHidden), isFalse);
    });

    test('legacy false migrates to false', () async {
      final prefs = await _prefs({WidgetPrefsKeys.legacyAmountsHidden: false});
      WidgetPositionsHiddenNotifier(prefs);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getBool(WidgetPrefsKeys.positionsHidden), isFalse);
    });

    test('no keys: stays false and writes nothing; idempotent', () async {
      final prefs = await _prefs({});
      final n = WidgetPositionsHiddenNotifier(prefs);
      WidgetPositionsHiddenNotifier(prefs);
      await Future<void>.delayed(Duration.zero);
      expect(n.state, isFalse);
      expect(prefs.containsKey(WidgetPrefsKeys.positionsHidden), isFalse);
    });
  });
}

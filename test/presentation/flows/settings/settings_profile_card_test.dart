import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_profile_card.dart';

/// Sin easy_localization cargado, `.tr()` devuelve la key.
Widget _app({String? name, required Future<bool> Function(String) onSave}) =>
    MaterialApp(
      theme: ProviderContainer().read(themeDataLightProvider),
      home: Scaffold(
        body: SettingsProfileCard(
          name: name,
          email: 'alfonso@example.com',
          onSaveName: onSave,
        ),
      ),
    );

void main() {
  test('initials: up to two words; without a name, the email', () {
    expect(SettingsProfileCard.initials('Alfonso Katz', 'a@b.c'), 'AK');
    expect(SettingsProfileCard.initials('alfonso', 'a@b.c'), 'A');
    expect(SettingsProfileCard.initials(null, 'zoe@b.c'), 'Z');
    expect(SettingsProfileCard.initials('  ', ''), '?');
  });

  testWidgets('without a name it invites to add one', (tester) async {
    await tester.pumpWidget(_app(onSave: (_) async => true));
    expect(find.text('settings_profile_add_name'), findsOneWidget);
    expect(find.text('alfonso@example.com'), findsOneWidget);
  });

  testWidgets('editing saves the trimmed name and closes the sheet', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      _app(name: 'Alfonso', onSave: (n) async => (saved = n) != null),
    );
    await tester.tap(find.text('settings_profile_edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Alfonso Katz  ');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(saved, 'Alfonso Katz');
    expect(find.byType(TextField), findsNothing, reason: 'la hoja se cerró');
  });

  testWidgets('an empty name is not saved', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(name: 'Alfonso', onSave: (_) async {
        calls++;
        return true;
      }),
    );
    await tester.tap(find.text('settings_profile_edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('auth_full_name_required'), findsOneWidget);
  });

  testWidgets('if saving fails, the sheet stays open', (tester) async {
    await tester.pumpWidget(_app(name: 'A', onSave: (_) async => false));
    await tester.tap(find.text('settings_profile_edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alfonso');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });
}

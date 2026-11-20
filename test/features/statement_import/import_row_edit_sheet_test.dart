// Corregir una fila importada: Porty dice qué no pudo leer. Correr:
// flutter test test/features/statement_import/import_row_edit_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';
import 'package:portfolio_assistant/features/statement_import/view/import_row_edit_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

void main() {
  setUpAll(() => PortyAvatar.ambientMotion = false);

  Future<void> pump(WidgetTester tester, ImportRow row) async {
    final probe = ProviderContainer();
    await tester.pumpWidget(
      MaterialApp(
        theme: probe.read(themeDataLightProvider),
        home: Scaffold(body: ImportRowEditSheet(row: row)),
      ),
    );
    await tester.pump();
  }

  testWidgets('ticker sin cotización: lo dice primero', (tester) async {
    await pump(
      tester,
      const ImportRow(
        id: 1,
        ticker: 'XYZ',
        quantity: 2,
        quote: QuoteCheck.notFound,
      ),
    );
    expect(find.text('import_edit_porty_ticker'), findsOneWidget);
  });

  testWidgets('sin precio de compra: pide el precio', (tester) async {
    await pump(
      tester,
      const ImportRow(
        id: 1,
        ticker: 'AAPL',
        quantity: 2,
        quote: QuoteCheck.found,
      ),
    );
    expect(find.text('import_edit_porty_price'), findsOneWidget);
  });

  testWidgets('con todo leído: pide revisar', (tester) async {
    await pump(
      tester,
      ImportRow(
        id: 1,
        ticker: 'AAPL',
        name: 'Apple',
        quantity: 2,
        purchasePrice: 150,
        purchaseDate: DateTime(2025, 3, 1),
        quote: QuoteCheck.found,
      ),
    );
    expect(find.text('import_edit_porty_review'), findsOneWidget);
    expect(find.text('AAPL · Apple'), findsOneWidget);
  });
}

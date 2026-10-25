import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/source_widgets.dart';
import 'package:portfolio_assistant/features/assistant/utils/answer_sources.dart';

import '../../../helpers/genui_test_helpers.dart';

void main() {
  const sources = [
    MessageSource(url: 'https://www.reuters.com/a', title: 'Nvidia unveils a chip', source: 'Reuters'),
    MessageSource(url: 'https://www.cnbc.com/b', title: 'Chips rally', source: 'CNBC'),
    MessageSource(url: 'https://www.infobae.com/c', title: 'Wall Street sube', source: 'Infobae'),
    MessageSource(url: 'https://www.sec.gov/d', title: 'Comunicado de resultados de NVDA (8-K)', source: 'SEC EDGAR'),
    MessageSource(url: 'https://www.ambito.com/e'),
  ];

  testWidgets('las citas se ven como links tocables; las de más, a pedido', (
    tester,
  ) async {
    await tester.pumpWidget(
      genuiTestApp(child: const QaSourceList(sources: sources)),
    );
    expect(find.text('FUENTES'), findsOneWidget);
    expect(find.textContaining('Nvidia unveils a chip'), findsOneWidget);
    expect(find.textContaining('SEC EDGAR'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsNWidgets(4));
    expect(find.text('Ver 1 más'), findsOneWidget);

    await tester.tap(find.text('Ver 1 más'));
    await tester.pump();
    expect(find.byIcon(Icons.open_in_new_rounded), findsNWidgets(5));
    // Sin medio ni título: el dominio.
    expect(find.textContaining('ambito.com'), findsOneWidget);

    final semantics = tester.getSemantics(find.byType(InkWell).first);
    expect(semantics.label, 'Reuters: Nvidia unveils a chip');
    expect(semantics.hasFlag(SemanticsFlag.isLink), isTrue);
  });
}

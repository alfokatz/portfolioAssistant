import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';

Widget _host(Widget child, {ValueChanged<String>? onFollowUp}) {
  final body = Scaffold(body: Center(child: child));
  return MaterialApp(
    home:
        onFollowUp == null
            ? body
            : QaFollowUpScope(onFollowUp: onFollowUp, child: body),
  );
}

class _CountingRepo implements CompanyBrandRepository {
  _CountingRepo(this.result);
  final CompanyBrand? result;
  int calls = 0;

  @override
  Future<CompanyBrand?> getBrand(String ticker) async {
    calls++;
    return result;
  }
}

void main() {
  group('QaFormat', () {
    test('signed values and plurals', () {
      expect(QaFormat.signedPct(4.061), '+4.06%');
      expect(QaFormat.signedPct(-1.96), '-1.96%');
      expect(QaFormat.signedMoney(428), '+\$428');
      expect(QaFormat.signedMoney(-7.4), '-\$7');
      expect(QaFormat.plural(1, 'posición', 'posiciones'), '1 posición');
      expect(QaFormat.plural(3, 'posición', 'posiciones'), '3 posiciones');
    });
  });

  group('QaDeltaChip', () {
    testWidgets('shows magnitude with a direction arrow instead of a sign', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const QaDeltaChip(value: -1.96)));
      expect(find.text('1.96%'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
    });
  });

  group('QaTickerAvatar', () {
    testWidgets('falls back to a monogram without a ProviderScope', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const QaTickerAvatar(ticker: 'VOO')));
      expect(find.text('VO'), findsOneWidget);
    });
  });

  group('follow-ups', () {
    testWidgets('bar is hidden without a QaFollowUpScope', (tester) async {
      await tester.pumpWidget(
        _host(QaFollowUpBar(items: QaTickerFollowUps.of('NVDA'))),
      );
      expect(find.text('Noticias'), findsNothing);
    });

    testWidgets('tapping a chip sends its question through the scope', (
      tester,
    ) async {
      final sent = <String>[];
      await tester.pumpWidget(
        _host(
          QaFollowUpBar(
            items:
                QaTickerFollowUps.of(
                  'NVDA',
                  exclude: {QaTickerFollowUps.chart},
                ).take(2).toList(),
          ),
          onFollowUp: sent.add,
        ),
      );
      expect(find.text('Gráfico'), findsNothing);
      await tester.tap(find.text('Noticias'));
      expect(sent, ['¿Qué noticias hay de NVDA?']);
    });

    testWidgets('ticker header asks about the ticker when tapped', (
      tester,
    ) async {
      final sent = <String>[];
      await tester.pumpWidget(
        _host(const QaTickerHeader(ticker: 'AAPL'), onFollowUp: sent.add),
      );
      await tester.tap(find.text('AAPL'));
      expect(sent, ['¿Cómo viene AAPL?']);
    });
  });

  group('CompanyBrandLoader', () {
    test('dedupes in-flight requests and caches successes', () async {
      final repo = _CountingRepo(
        const CompanyBrand(ticker: 'AAPL', name: 'Apple Inc'),
      );
      final loader = CompanyBrandLoader(repo);
      final results = await Future.wait([
        loader.load('aapl'),
        loader.load('AAPL'),
      ]);
      expect(results.map((b) => b.name), ['Apple Inc', 'Apple Inc']);
      await loader.load('AAPL');
      expect(repo.calls, 1);
      expect(loader.peek('AAPL')?.name, 'Apple Inc');
    });

    test('does not cache transient failures', () async {
      final repo = _CountingRepo(null);
      final loader = CompanyBrandLoader(repo);
      final brand = await loader.load('XYZ');
      expect(brand.name, isNull);
      await loader.load('XYZ');
      expect(repo.calls, 2);
    });
  });
}

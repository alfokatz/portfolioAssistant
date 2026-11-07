import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';

/// Falla (null, no se cachea) las primeras [failures] veces por ticker.
class _Flaky implements CompanyBrandRepository {
  _Flaky({this.failures = 0});
  final int failures;
  final calls = <String, int>{};

  @override
  Future<CompanyBrand?> getBrand(String ticker) async {
    final n = calls[ticker] = (calls[ticker] ?? 0) + 1;
    if (n <= failures) return null;
    return CompanyBrand(ticker: ticker, name: 'Name of $ticker');
  }
}

Widget _app(CompanyBrandLoader loader, String ticker) => UncontrolledProviderScope(
  container: ProviderContainer(
    overrides: [companyBrandLoaderProvider.overrideWithValue(loader)],
  ),
  child: MaterialApp(
    home: QaBrandBuilder(
      ticker: ticker,
      builder: (_, brand) => Text(brand.name ?? 'monogram ${brand.ticker}'),
    ),
  ),
);

void main() {
  testWidgets('a transient failure is retried (bug 2026-10-06: the logo '
      'stayed a monogram forever)', (tester) async {
    final repo = _Flaky(failures: 1);
    final loader = CompanyBrandLoader(repo);
    await tester.pumpWidget(_app(loader, 'AMZN'));
    await tester.pump();
    expect(find.text('monogram AMZN'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Name of AMZN'), findsOneWidget);
    expect(repo.calls['AMZN'], 2);
  });

  testWidgets('gives up after a few retries', (tester) async {
    final repo = _Flaky(failures: 99);
    await tester.pumpWidget(_app(CompanyBrandLoader(repo), 'AMZN'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 20));
    }
    expect(repo.calls['AMZN'], 4); // 1 + 3 reintentos
  });

  testWidgets('the same row with another ticker shows the new brand', (
    tester,
  ) async {
    final loader = CompanyBrandLoader(_Flaky());
    await tester.pumpWidget(_app(loader, 'VOO'));
    await tester.pump();
    expect(find.text('Name of VOO'), findsOneWidget);

    await tester.pumpWidget(_app(loader, 'AMZN'));
    await tester.pump();
    expect(find.text('Name of AMZN'), findsOneWidget);
  });
}

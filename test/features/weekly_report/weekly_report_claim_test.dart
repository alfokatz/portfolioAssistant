import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_claim.dart';

void main() {
  test('parses every server state', () {
    final ready = WeeklyReportClaim.parse({
      'state': 'ready',
      'payload': {'headline': 'Semana tranquila'},
      'courtesy': true,
    });
    expect(ready, isA<ClaimReady>());
    expect((ready as ClaimReady).payload['headline'], 'Semana tranquila');
    expect(ready.courtesy, isTrue);

    final claimed = WeeklyReportClaim.parse({
      'state': 'claimed',
      'courtesy': false,
      'attempt': 2,
    });
    expect((claimed as ClaimGranted).attempt, 2);
    expect(claimed.courtesy, isFalse);

    expect(
      WeeklyReportClaim.parse({'state': 'in_progress'}),
      isA<ClaimInProgress>(),
    );
    expect(
      WeeklyReportClaim.parse({'state': 'numbers_only'}),
      isA<ClaimNumbersOnly>(),
    );
    expect(WeeklyReportClaim.parse({'state': 'failed'}), isA<ClaimFailed>());
    expect(
      WeeklyReportClaim.parse({'state': 'disabled'}),
      isA<ClaimDisabled>(),
    );
  });

  test('anything unexpected means "unavailable", never a crash', () {
    expect(WeeklyReportClaim.parse(null), isA<ClaimUnavailable>());
    expect(WeeklyReportClaim.parse('x'), isA<ClaimUnavailable>());
    expect(
      WeeklyReportClaim.parse({'state': 'ready'}), // sin payload
      isA<ClaimUnavailable>(),
    );
    expect(
      WeeklyReportClaim.parse({'state': 'other'}),
      isA<ClaimUnavailable>(),
    );
  });
}

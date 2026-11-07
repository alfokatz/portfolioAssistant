import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';

void main() {
  // Semana bursátil del lunes 21 al viernes 25 de septiembre de 2026.
  final week = ReportWeek.ofMonday(DateTime(2026, 9, 21));

  test('on the weekend it covers the week that just closed', () {
    expect(ReportWeek.coveredAt(DateTime(2026, 9, 26)), week); // sábado 00:00
    expect(ReportWeek.coveredAt(DateTime(2026, 9, 27, 23, 59)), week);
  });

  test('Monday to Friday it still shows the previous closed week', () {
    expect(ReportWeek.coveredAt(DateTime(2026, 9, 28, 9)), week);
    expect(ReportWeek.coveredAt(DateTime(2026, 10, 2, 23, 59)), week);
    // El viernes de la propia semana todavía no cerró: muestra la anterior.
    expect(ReportWeek.coveredAt(DateTime(2026, 9, 25, 18)).key, '2026-09-14');
  });

  test('exposes the trading days, the key and the next week', () {
    expect(week.key, '2026-09-21');
    expect(week.friday, DateTime(2026, 9, 25));
    expect(week.endExclusive, DateTime(2026, 9, 26));
    expect(week.next.monday, DateTime(2026, 9, 28));
    expect(week.next.friday, DateTime(2026, 10, 2));
  });

  test('crossing a month and a year boundary', () {
    final w = ReportWeek.ofMonday(DateTime(2026, 12, 28));
    expect(w.friday, DateTime(2027, 1, 1));
    expect(w.next.key, '2027-01-04');
  });
}

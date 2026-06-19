import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/invest_fit_scorer.dart';

void main() {
  group('computeFitScore', () {
    test('returns 100 when all factors are optimal', () {
      expect(
        computeFitScore(
          fetchOk: true,
          hasBudget: true,
          addsDiversification: true,
          sectorOverlapPct: null,
        ),
        100,
      );
    });

    test('returns 0 when all factors fail', () {
      expect(
        computeFitScore(
          fetchOk: false,
          hasBudget: false,
          addsDiversification: false,
          sectorOverlapPct: 100,
        ),
        0,
      );
    });

    test('penalizes sector overlap when not diversifying', () {
      final score = computeFitScore(
        fetchOk: true,
        hasBudget: true,
        addsDiversification: false,
        sectorOverlapPct: 50,
      );
      expect(score, 80);
    });

    test('awards partial diversification score at 40% overlap', () {
      final score = computeFitScore(
        fetchOk: false,
        hasBudget: false,
        addsDiversification: false,
        sectorOverlapPct: 40,
      );
      expect(score, 24);
    });
  });
}

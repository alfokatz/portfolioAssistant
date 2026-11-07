import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/invest_fit_scorer.dart';

void main() {
  group('computeFitScore', () {
    test('returns 100 when all factors are optimal', () {
      expect(
        computeFitScore(
          fetchOk: true,
          addsDiversification: true,
          sectorOverlapPct: null,
          matchesProfile: true,
        ),
        100,
      );
    });

    test('returns 0 when all factors fail', () {
      expect(
        computeFitScore(
          fetchOk: false,
          addsDiversification: false,
          sectorOverlapPct: 100,
          matchesProfile: false,
        ),
        0,
      );
    });

    test('an unknown profile scores neutral, not zero', () {
      expect(
        computeFitScore(
          fetchOk: true,
          addsDiversification: true,
          sectorOverlapPct: null,
        ),
        85,
      );
    });

    test('penalizes sector overlap when not diversifying', () {
      final score = computeFitScore(
        fetchOk: true,
        addsDiversification: false,
        sectorOverlapPct: 50,
        matchesProfile: true,
      );
      expect(score, 75);
    });

    test('awards partial diversification score at 40% overlap', () {
      final score = computeFitScore(
        fetchOk: false,
        addsDiversification: false,
        sectorOverlapPct: 40,
        matchesProfile: false,
      );
      expect(score, 30);
    });
  });

  group('FitTier', () {
    test('maps the score to a human label', () {
      expect(FitTier.of(85).label, 'Buen encaje');
      expect(FitTier.of(75), FitTier.good);
      expect(FitTier.of(60), FitTier.medium);
      expect(FitTier.of(30), FitTier.low);
    });
  });
}

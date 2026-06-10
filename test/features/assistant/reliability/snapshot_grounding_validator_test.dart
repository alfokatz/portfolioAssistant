import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/reliability/snapshot_grounding_validator.dart';

void main() {
  group('SnapshotGroundingValidator', () {
    group('portfolio mode', () {
      test('returns ok when has_portfolio_data is true', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.portfolio,
          snapshot: {'has_portfolio_data': true},
        );
        expect(result, SnapshotValidation.ok);
      });

      test('returns noPortfolioData when has_portfolio_data is false', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.portfolio,
          snapshot: {'has_portfolio_data': false},
        );
        expect(result, SnapshotValidation.noPortfolioData);
      });

      test('returns noPortfolioData when has_portfolio_data is missing', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.portfolio,
          snapshot: {},
        );
        expect(result, SnapshotValidation.noPortfolioData);
      });
    });

    group('explore mode', () {
      test('returns ok when at least one ticker has fetch_ok true', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.explore,
          snapshot: {
            'explore_tickers': {
              'AAPL': {'fetch_ok': true, 'current_price': 190.0},
              'FAKE': {'fetch_ok': false},
            },
          },
        );
        expect(result, SnapshotValidation.ok);
      });

      test('returns exploreFetchFailed when all tickers have fetch_ok false', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.explore,
          snapshot: {
            'explore_tickers': {
              'FAKE1': {'fetch_ok': false},
              'FAKE2': {'fetch_ok': false},
            },
          },
        );
        expect(result, SnapshotValidation.exploreFetchFailed);
      });

      test('returns exploreFetchFailed when explore_tickers is empty', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.explore,
          snapshot: {'explore_tickers': <String, dynamic>{}},
        );
        expect(result, SnapshotValidation.exploreFetchFailed);
      });

      test('returns exploreFetchFailed when explore_tickers is null', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.explore,
          snapshot: {},
        );
        expect(result, SnapshotValidation.exploreFetchFailed);
      });
    });

    group('invest mode', () {
      test('returns ok when at least one candidate has fetch_ok true', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.invest,
          snapshot: {
            'candidates': [
              {'ticker': 'NVDA', 'fetch_ok': true},
              {'ticker': 'FAKE', 'fetch_ok': false},
            ],
          },
        );
        expect(result, SnapshotValidation.ok);
      });

      test('returns exploreFetchFailed when all candidates have fetch_ok false', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.invest,
          snapshot: {
            'candidates': [
              {'ticker': 'FAKE1', 'fetch_ok': false},
              {'ticker': 'FAKE2', 'fetch_ok': false},
            ],
          },
        );
        expect(result, SnapshotValidation.exploreFetchFailed);
      });

      test('returns exploreFetchFailed when candidates is empty', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.invest,
          snapshot: {'candidates': <Map<String, dynamic>>[]},
        );
        expect(result, SnapshotValidation.exploreFetchFailed);
      });

      test('returns exploreFetchFailed when candidates is null', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.invest,
          snapshot: {},
        );
        expect(result, SnapshotValidation.exploreFetchFailed);
      });
    });

    group('learn and plan modes', () {
      test('learn mode always returns ok', () {
        expect(
          SnapshotGroundingValidator.validate(
            mode: AssistantMode.learn,
            snapshot: {},
          ),
          SnapshotValidation.ok,
        );
      });

      test('plan mode always returns ok', () {
        expect(
          SnapshotGroundingValidator.validate(
            mode: AssistantMode.plan,
            snapshot: {},
          ),
          SnapshotValidation.ok,
        );
      });

      test('plan mode returns ok when projection requested but goal incomplete', () {
        expect(
          SnapshotGroundingValidator.validate(
            mode: AssistantMode.plan,
            snapshot: {
              'has_complete_goal': false,
              'projection': null,
            },
          ),
          SnapshotValidation.ok,
        );
      });
    });
  });
}

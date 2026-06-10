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
      test('returns ok when explore_tickers is non-empty', () {
        final result = SnapshotGroundingValidator.validate(
          mode: AssistantMode.explore,
          snapshot: {
            'explore_tickers': {'AAPL': {'price': 190.0}},
          },
        );
        expect(result, SnapshotValidation.ok);
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

    group('learn, invest, plan modes', () {
      test('learn mode always returns ok', () {
        expect(
          SnapshotGroundingValidator.validate(
            mode: AssistantMode.learn,
            snapshot: {},
          ),
          SnapshotValidation.ok,
        );
      });

      test('invest mode always returns ok', () {
        expect(
          SnapshotGroundingValidator.validate(
            mode: AssistantMode.invest,
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
    });
  });
}

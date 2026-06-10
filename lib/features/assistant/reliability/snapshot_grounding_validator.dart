import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

enum SnapshotValidation { ok, noPortfolioData, exploreFetchFailed, partial }

abstract final class SnapshotGroundingValidator {
  static SnapshotValidation validate({
    required AssistantMode mode,
    required Map<String, dynamic> snapshot,
  }) {
    switch (mode) {
      case AssistantMode.portfolio:
        if (snapshot['has_portfolio_data'] != true) {
          return SnapshotValidation.noPortfolioData;
        }
        return SnapshotValidation.ok;
      case AssistantMode.explore:
        final tickers = snapshot['explore_tickers'] as Map?;
        if (tickers == null || tickers.isEmpty) {
          return SnapshotValidation.exploreFetchFailed;
        }
        final hasSuccessfulFetch = tickers.values.any((entry) {
          if (entry is! Map) return false;
          return entry['fetch_ok'] == true;
        });
        if (!hasSuccessfulFetch) {
          return SnapshotValidation.exploreFetchFailed;
        }
        return SnapshotValidation.ok;
      case AssistantMode.learn:
      case AssistantMode.invest:
      case AssistantMode.plan:
        return SnapshotValidation.ok;
    }
  }
}

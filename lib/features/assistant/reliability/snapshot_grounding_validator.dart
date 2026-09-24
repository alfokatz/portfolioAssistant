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
        // No hay ticker resuelto, pero sí un nombre de compañía ambiguo
        // (2+ matches) — dejar pasar para que el modelo pida aclaración en
        // lenguaje natural, en vez de cortar con el error técnico genérico.
        if (snapshot['explore_ticker_ambiguous'] != null) {
          return SnapshotValidation.ok;
        }
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
      case AssistantMode.invest:
        final candidates = snapshot['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          return SnapshotValidation.exploreFetchFailed;
        }
        final hasOk = candidates.any((c) => c is Map && c['fetch_ok'] == true);
        if (!hasOk) return SnapshotValidation.exploreFetchFailed;
        return SnapshotValidation.ok;
      case AssistantMode.learn:
      case AssistantMode.plan:
        return SnapshotValidation.ok;
    }
  }
}

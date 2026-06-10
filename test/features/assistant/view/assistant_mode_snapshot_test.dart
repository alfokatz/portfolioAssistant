import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_snapshot_builder.dart';

void main() {
  group('buildSnapshotJson', () {
    final fixedAsOf = DateTime.utc(2026, 6, 10, 12, 0);

    test('learn mode returns minimal snapshot with mode learn', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.learn,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'learn');
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
      expect(snapshot.containsKey('has_portfolio_data'), isFalse);
    });

    test('explore mode returns placeholder explore_tickers', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.explore,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'explore');
      expect(snapshot['explore_tickers'], isEmpty);
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
    });

    test('invest mode returns minimal snapshot with mode name', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.invest,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'invest');
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
    });

    test('plan mode returns minimal snapshot with mode name', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.plan,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'plan');
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
    });

    test('portfolio mode without data returns has_portfolio_data false', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.portfolio,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['has_portfolio_data'], isFalse);
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
    });
  });
}

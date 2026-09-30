import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_skeleton.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/paywall_source_log.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Repo implements SubscriptionRepository {
  @override
  Future<SubscriptionStatus> fetchStatus() async => const SubscriptionStatus(
    tier: SubscriptionTier.premium,
    queriesUsed: 40,
    queriesLimit: 500,
    month: '2026-09',
  );

  @override
  Future<bool> consumeQuota(int weight) async => true;
}

class _Session implements SupabaseAuthService {
  @override
  Session? get currentSession => Session(
    accessToken: 't',
    tokenType: 'bearer',
    user: const User(
      id: 'u',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Precios que tardan: la hoja tiene que abrirse igual, con skeletons.
class _SlowPrices implements RevenueCatService {
  final prices = Completer<Map<SubscriptionTier, String>>();

  @override
  Future<Map<SubscriptionTier, String>> fetchTierPrices() => prices.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('opens at once in Gold with the preview, skeleton prices, '
      'records its source and gives a light haptic', (tester) async {
    PaywallSourceLog.clear();
    final haptics = <PortyHapticPattern>[];
    final revenueCat = _SlowPrices();
    final tracker = AiUsageTracker(repository: _Repo());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portyHapticsServiceProvider.overrideWithValue(
            PortyHapticsService(
              enabled: true,
              performer: (p) async => haptics.add(p),
            ),
          ),
          aiUsageTrackerProvider.overrideWithValue(tracker),
          revenueCatServiceProvider.overrideWithValue(revenueCat),
          subscriptionProvider.overrideWith(
            (ref) => SubscriptionNotifier(
              tracker: tracker,
              authService: _Session(),
              revenueCat: revenueCat,
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [CustomColors.light]),
          home: Consumer(
            builder:
                (context, ref, _) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed:
                          () => SubscriptionPaywallSheet.show(
                            context,
                            ref,
                            reason: PaywallReason.goldRequired,
                            source: 'analysis_locked_news',
                            preview: (_) => const Text('PREVIEW BAC'),
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(PaywallSourceLog.recent, ['analysis_locked_news']);
    expect(haptics, [PortyHapticPattern.light]);
    expect(find.text('PREVIEW BAC'), findsOneWidget);
    // Solo Gold (se abrió desde algo de Gold), con su lista de la matriz.
    expect(find.text('paywall_upgrade_gold'), findsOneWidget);
    expect(find.text('paywall_upgrade_premium'), findsNothing);
    expect(find.text('plan_feature_company_analysis'), findsOneWidget);
    // Los precios todavía no llegaron: skeleton en su lugar.
    expect(find.byType(QaSkeleton), findsOneWidget);

    revenueCat.prices.complete({SubscriptionTier.gold: 'US\$19.99'});
    await tester.pump();
    await tester.pump();
    expect(find.byType(QaSkeleton), findsNothing);
  });
}

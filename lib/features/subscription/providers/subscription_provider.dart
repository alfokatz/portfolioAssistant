import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/infraestructure/repositories/subscription_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PaywallReason {
  modeLocked,
  newsRequiresGold,
  quotaExceeded,
}

class SubscriptionState {
  final SubscriptionTier tier;
  final int queriesUsed;
  final int queriesLimit;
  final bool isLoading;
  final bool isPurchasing;

  const SubscriptionState({
    required this.tier,
    required this.queriesUsed,
    required this.queriesLimit,
    this.isLoading = false,
    this.isPurchasing = false,
  });

  int get queriesRemaining =>
      (queriesLimit - queriesUsed).clamp(0, queriesLimit);

  SubscriptionState copyWith({
    SubscriptionTier? tier,
    int? queriesUsed,
    int? queriesLimit,
    bool? isLoading,
    bool? isPurchasing,
  }) {
    return SubscriptionState(
      tier: tier ?? this.tier,
      queriesUsed: queriesUsed ?? this.queriesUsed,
      queriesLimit: queriesLimit ?? this.queriesLimit,
      isLoading: isLoading ?? this.isLoading,
      isPurchasing: isPurchasing ?? this.isPurchasing,
    );
  }

  static const initial = SubscriptionState(
    tier: SubscriptionTier.free,
    queriesUsed: 0,
    queriesLimit: AiUsageLimits.freeMonthly,
    isLoading: true,
  );
}

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  SubscriptionNotifier({
    required AiUsageTracker tracker,
    required SupabaseAuthService authService,
    required RevenueCatService revenueCat,
  })  : _tracker = tracker,
        _authService = authService,
        _revenueCat = revenueCat,
        super(SubscriptionState.initial) {
    load();
  }

  final AiUsageTracker _tracker;
  final SupabaseAuthService _authService;
  final RevenueCatService _revenueCat;

  Future<void> load() => refresh();

  Future<void> refresh() async {
    if (_authService.currentSession == null) {
      state = const SubscriptionState(
        tier: SubscriptionTier.free,
        queriesUsed: 0,
        queriesLimit: AiUsageLimits.freeMonthly,
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final status = await _tracker.getStatus();
      state = SubscriptionState(
        tier: status.tier,
        queriesUsed: status.queriesUsed,
        queriesLimit: status.queriesLimit,
        isLoading: false,
        isPurchasing: state.isPurchasing,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  bool canAccessMode(AssistantMode mode) {
    return SubscriptionPolicy.isModeAllowed(state.tier, mode);
  }

  Future<PaywallReason?> checkQueryAllowed({
    required AssistantMode mode,
    required bool isNewsQuery,
  }) async {
    await refresh();

    if (!canAccessMode(mode)) {
      return PaywallReason.modeLocked;
    }
    if (isNewsQuery && !SubscriptionPolicy.isNewsAllowed(state.tier)) {
      return PaywallReason.newsRequiresGold;
    }
    final weight = SubscriptionPolicy.queryWeight(isNewsQuery: isNewsQuery);
    if (!await _tracker.canConsume(weight)) {
      return PaywallReason.quotaExceeded;
    }
    return null;
  }

  Future<RevenueCatPurchaseResult> purchaseTier(SubscriptionTier tier) async {
    state = state.copyWith(isPurchasing: true);
    try {
      final result = await _revenueCat.purchaseTier(tier);
      if (result is RevenueCatPurchaseSuccess) {
        await _refreshAfterPurchase(expectedTier: tier);
      }
      return result;
    } finally {
      state = state.copyWith(isPurchasing: false);
    }
  }

  Future<RevenueCatPurchaseResult> restorePurchases() async {
    state = state.copyWith(isPurchasing: true);
    try {
      final result = await _revenueCat.restorePurchases();
      if (result is RevenueCatPurchaseSuccess) {
        await _refreshAfterPurchase();
      }
      return result;
    } finally {
      state = state.copyWith(isPurchasing: false);
    }
  }

  /// El webhook de RevenueCat puede tardar unos segundos en actualizar Supabase.
  Future<void> _refreshAfterPurchase({SubscriptionTier? expectedTier}) async {
    const delaysMs = [500, 1500, 2000, 2500, 3000];
    for (final delay in delaysMs) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      await refresh();
      if (expectedTier != null && state.tier == expectedTier) return;
      if (expectedTier == null && state.tier != SubscriptionTier.free) return;
    }
  }
}

final aiUsageTrackerProvider = Provider<AiUsageTracker>(
  (ref) => AiUsageTracker(
    repository: ref.watch(subscriptionRepositoryProvider),
  ),
);

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>(
  (ref) {
    final notifier = SubscriptionNotifier(
      tracker: ref.watch(aiUsageTrackerProvider),
      authService: ref.watch(supabaseAuthServiceProvider),
      revenueCat: ref.watch(revenueCatServiceProvider),
    );

    ref.listen<AsyncValue<Session?>>(authSessionProvider, (previous, next) {
      final wasAuthed = previous?.value != null;
      final isAuthed = next.value != null;
      if (wasAuthed != isAuthed) {
        notifier.refresh();
      }
    });

    return notifier;
  },
);

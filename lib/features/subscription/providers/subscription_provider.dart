import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/paywall_offer.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/infraestructure/repositories/subscription_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PaywallReason {
  /// Función de Premium fuera del plan sin un motivo propio (benchmark,
  /// operaciones de cartera, S&P del informe).
  modeLocked,

  /// "Ver planes" sin un motivo puntual (Ajustes).
  plans,

  /// Llegó al tope de posiciones del plan.
  positionLimit,

  /// Simulaciones de aportes (`PlanFeature.investSimulation`).
  simulations,

  /// Metas con plan de aportes (`PlanFeature.goals`).
  goals,

  /// Plan de cartera (`PlanFeature.allocationPlan`).
  allocationPlan,

  /// El asistente pidió datos de mercado de tickers que el usuario no tiene.
  marketDataLocked,

  /// Datos de Gold: análisis, noticias, earnings, fundamentals.
  goldRequired,
  quotaExceeded,

  /// Quedan pocas consultas del mes (la línea del chat). Como
  /// [quotaExceeded] pero todavía puede consultar.
  quotaLow,

  /// Conectar eToro (Premium y Gold).
  brokerSync,

  /// Llegó al tope de alertas de precio activas de su plan.
  priceAlerts,

  /// Comparar la cartera contra el S&P 500 (`PlanFeature.benchmark`).
  benchmark,

  /// Llegó al tope de tickers en seguimiento de su plan.
  watchlistLimit,

  /// Noticias de lo que tiene en cartera (`PlanFeature.heldNews`).
  heldNews;

  /// Qué plan se ofrece primero: `premium`, `gold` o `null` (sin
  /// preferencia: el paywall muestra Gold y Premium). [currentTier] solo
  /// importa para la cuota: a un Free se le ofrece Premium.
  SubscriptionTier? offerTier({
    SubscriptionTier currentTier = SubscriptionTier.free,
  }) => switch (this) {
    PaywallReason.positionLimit ||
    PaywallReason.simulations ||
    PaywallReason.goals ||
    PaywallReason.allocationPlan ||
    PaywallReason.marketDataLocked ||
    PaywallReason.brokerSync ||
    PaywallReason.priceAlerts ||
    PaywallReason.benchmark ||
    PaywallReason.watchlistLimit ||
    PaywallReason.heldNews => SubscriptionTier.premium,
    PaywallReason.quotaExceeded ||
    PaywallReason.quotaLow =>
      currentTier == SubscriptionTier.free ? SubscriptionTier.premium : null,
    PaywallReason.goldRequired => SubscriptionTier.gold,
    // modeLocked se borra en la fase C (F6); mientras tanto no tiene oferta.
    PaywallReason.modeLocked || PaywallReason.plans => null,
  };
}

class SubscriptionState {
  final SubscriptionTier tier;
  final int queriesUsed;
  final int queriesLimit;
  final bool isLoading;
  final SubscriptionTier? purchasingTier;
  final bool isRestoring;

  const SubscriptionState({
    required this.tier,
    required this.queriesUsed,
    required this.queriesLimit,
    this.isLoading = false,
    this.purchasingTier,
    this.isRestoring = false,
  });

  bool get isPurchasing => purchasingTier != null || isRestoring;

  int get queriesRemaining =>
      (queriesLimit - queriesUsed).clamp(0, queriesLimit);

  SubscriptionState copyWith({
    SubscriptionTier? tier,
    int? queriesUsed,
    int? queriesLimit,
    bool? isLoading,
    SubscriptionTier? purchasingTier,
    bool? isRestoring,
    bool clearPurchasingTier = false,
  }) {
    return SubscriptionState(
      tier: tier ?? this.tier,
      queriesUsed: queriesUsed ?? this.queriesUsed,
      queriesLimit: queriesLimit ?? this.queriesLimit,
      isLoading: isLoading ?? this.isLoading,
      purchasingTier:
          clearPurchasingTier ? null : (purchasingTier ?? this.purchasingTier),
      isRestoring: isRestoring ?? this.isRestoring,
    );
  }

  static final initial = SubscriptionState(
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
  }) : _tracker = tracker,
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
      state = SubscriptionState(
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
        purchasingTier: state.purchasingTier,
        isRestoring: state.isRestoring,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Chequeo de cuota antes de un turno del asistente. El gating por dato
  /// lo hace cada tool al ejecutarse.
  Future<PaywallReason?> checkQuotaAllowed({int weight = 1}) async {
    await refresh();
    if (!await _tracker.canConsume(weight)) {
      return PaywallReason.quotaExceeded;
    }
    return null;
  }

  /// Compra [tier] en [period]; [source] es desde dónde se abrió el
  /// paywall (ver `PaywallSource`).
  Future<RevenueCatPurchaseResult> purchaseTier(
    SubscriptionTier tier, {
    BillingPeriod period = BillingPeriod.monthly,
    required String source,
  }) async {
    state = state.copyWith(purchasingTier: tier);
    try {
      final result = await _revenueCat.purchase(tier, period, source: source);
      if (result is RevenueCatPurchaseSuccess) {
        await _refreshAfterPurchase(expectedTier: tier);
      }
      return result;
    } finally {
      state = state.copyWith(clearPurchasingTier: true, isRestoring: false);
    }
  }

  Future<RevenueCatPurchaseResult> restorePurchases() async {
    state = state.copyWith(isRestoring: true);
    try {
      final result = await _revenueCat.restorePurchases();
      if (result is RevenueCatPurchaseSuccess) {
        await _refreshAfterPurchase();
      }
      return result;
    } finally {
      state = state.copyWith(isRestoring: false);
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
  (ref) =>
      AiUsageTracker(repository: ref.watch(subscriptionRepositoryProvider)),
);

/// Precios mensuales y anuales que muestra el paywall (vacío sin
/// RevenueCat). El paywall lo invalida al abrirse.
final paywallOfferProvider = FutureProvider<PaywallOffer>((ref) async {
  return ref.read(revenueCatServiceProvider).fetchOffer();
});

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
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
    });

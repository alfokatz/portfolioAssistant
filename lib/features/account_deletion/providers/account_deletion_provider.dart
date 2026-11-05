import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/account_deletion/data/account_deletion_repository.dart';
import 'package:portfolio_assistant/features/account_deletion/data/subscription_store_probe.dart';
import 'package:portfolio_assistant/features/account_deletion/domain/account_deletion.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:url_launcher/url_launcher.dart';

@immutable
class AccountDeletionState {
  const AccountDeletionState({
    this.notice = DeletionStoreNotice.none,
    this.deleting = false,
    this.failure,
  });

  final DeletionStoreNotice notice;
  final bool deleting;
  final AccountDeletionFailure? failure;
}

class AccountDeletionNotifier extends StateNotifier<AccountDeletionState> {
  AccountDeletionNotifier({
    required AccountDeletionRepository repository,
    required SubscriptionStoreProbe probe,
  }) : _repository = repository,
       _probe = probe,
       super(const AccountDeletionState());

  final AccountDeletionRepository _repository;
  final SubscriptionStoreProbe _probe;

  Future<DeletionStoreNotice> loadNotice() async {
    final notice = await _probe.notice();
    if (mounted) state = AccountDeletionState(notice: notice);
    return notice;
  }

  /// `true` si borró. Ignora un segundo pedido mientras corre el primero.
  Future<bool> delete() async {
    if (state.deleting) return false;
    state = AccountDeletionState(notice: state.notice, deleting: true);
    final failure = await _repository.deleteAccount();
    if (mounted) {
      state = AccountDeletionState(notice: state.notice, failure: failure);
    }
    return failure == null;
  }
}

final subscriptionStoreProbeProvider = Provider<SubscriptionStoreProbe>(
  (ref) => SubscriptionStoreProbe(
    isConfigured: () => ref.read(revenueCatServiceProvider).isConfigured,
    serverTier: () => ref.read(subscriptionProvider).tier,
  ),
);

final accountDeletionProvider =
    StateNotifierProvider<AccountDeletionNotifier, AccountDeletionState>(
      (ref) => AccountDeletionNotifier(
        repository: ref.watch(accountDeletionRepositoryProvider),
        probe: ref.watch(subscriptionStoreProbeProvider),
      ),
    );

/// Abre la página de suscripciones de la tienda afuera de la app (costura
/// para tests).
final storeLinkLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

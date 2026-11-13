import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
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

/// Costura para Sign in with Apple al borrar: si hace falta el código y cómo
/// pedirlo (la hoja de Apple).
class AppleRevocation {
  const AppleRevocation({required this.needed, required this.requestCode});

  const AppleRevocation.none()
    : needed = _never,
      requestCode = _noCode;

  final bool Function() needed;

  /// `null` si el usuario cerró la hoja de Apple.
  final Future<String?> Function() requestCode;

  static bool _never() => false;
  static Future<String?> _noCode() async => null;
}

class AccountDeletionNotifier extends StateNotifier<AccountDeletionState> {
  AccountDeletionNotifier({
    required AccountDeletionRepository repository,
    required SubscriptionStoreProbe probe,
    AppleRevocation apple = const AppleRevocation.none(),
  }) : _repository = repository,
       _probe = probe,
       _apple = apple,
       super(const AccountDeletionState());

  final AccountDeletionRepository _repository;
  final SubscriptionStoreProbe _probe;
  final AppleRevocation _apple;

  Future<DeletionStoreNotice> loadNotice() async {
    final notice = await _probe.notice();
    if (mounted) state = AccountDeletionState(notice: notice);
    return notice;
  }

  /// `true` si borró. Ignora un segundo pedido mientras corre el primero.
  ///
  /// Con una cuenta de Apple, primero pide a Apple un código para que el
  /// servidor revoque el acceso (guía 5.1.1(v)). Si el usuario cierra la
  /// hoja de Apple, no se borra nada; si Apple falla, se borra igual (la
  /// revocación es best effort, como la de eToro).
  Future<bool> delete() async {
    if (state.deleting) return false;
    state = AccountDeletionState(notice: state.notice, deleting: true);

    String? appleCode;
    bool appleNeeded;
    try {
      appleNeeded = _apple.needed();
    } catch (_) {
      appleNeeded = false;
    }
    if (appleNeeded) {
      try {
        appleCode = await _apple.requestCode();
        if (appleCode == null) {
          if (mounted) state = AccountDeletionState(notice: state.notice);
          return false;
        }
      } catch (_) {
        appleCode = null;
      }
    }

    final failure = await _repository.deleteAccount(
      appleAuthorizationCode: appleCode,
    );
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
        apple: AppleRevocation(
          needed: () => ref.read(supabaseAuthServiceProvider).canRevokeApple,
          requestCode: () =>
              ref.read(supabaseAuthServiceProvider).appleAuthorizationCode(),
        ),
      ),
    );

/// Abre la página de suscripciones de la tienda afuera de la app (costura
/// para tests).
final storeLinkLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

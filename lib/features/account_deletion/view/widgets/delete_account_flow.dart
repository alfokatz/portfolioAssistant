import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/legal/legal_links.dart';
import 'package:portfolio_assistant/config/supabase/session_scope.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/account_deletion/domain/account_deletion.dart';
import 'package:portfolio_assistant/features/account_deletion/providers/account_deletion_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/auth/nav/auth_router.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/confirm_sheet.dart';

/// "Eliminar cuenta" de Ajustes: aviso de suscripción → confirmación →
/// progreso → login con un toast. Usa el contenedor de Riverpod y no un
/// `ref`: al cerrar sesión la pantalla de Ajustes se desmonta y el flujo
/// todavía tiene que mostrar el resultado.
abstract final class DeleteAccountFlow {
  static Future<void> run(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final notifier = container.read(accountDeletionProvider.notifier);
    final auth = container.read(supabaseAuthServiceProvider);
    final alerts = container.read(alertProvider.notifier);

    // Antes de borrar: después ya no hay usuario del cual leerlo.
    final user = auth.currentUser;
    final uid = user?.id;
    final usedApple = _usedApple(user?.appMetadata);

    final notice = await notifier.loadNotice();
    if (!context.mounted) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'settings_delete_account_title'.tr(),
      body: 'settings_delete_account_message'.tr(),
      confirmLabel: 'settings_delete_account'.tr(),
      notice:
          notice == DeletionStoreNotice.none
              ? null
              : _SubscriptionNotice(
                notice: notice,
                onOpenStore: (uri) async {
                  final opened = await container.read(
                    storeLinkLauncherProvider,
                  )(uri);
                  if (!opened) {
                    alerts.showError(message: 'settings_link_error'.tr());
                  }
                },
              ),
    );
    if (!confirmed || !context.mounted) return;

    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    // Sin esperar: la hoja de progreso vive hasta que termine el pedido.
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      builder: (_) => const _DeletingSheet(),
    );
    final deleted = await notifier.delete();
    navigator.pop();

    /// Cierra la sesión local y muestra [toast] en el login. Al cerrar
    /// sesión SessionScope monta la app con un contenedor nuevo (el login
    /// ya montado): el toast va a las alertas de ese contenedor. Si la
    /// sesión no se cerró, el camino de antes con el contenedor actual.
    Future<void> signOutToLogin(
      void Function(AlertProvider alerts) toast,
    ) async {
      final cancel = SessionScope.runAfterRestart(
        (fresh) => toast(fresh.read(alertProvider.notifier)),
      );
      await _signOutLocal(auth);
      if (auth.currentUser == null) return;
      cancel();
      router.go(AuthRouter.loginPath);
      // El toast lo dibuja la pantalla de login: esperar a que se monte.
      WidgetsBinding.instance.addPostFrameCallback((_) => toast(alerts));
      WidgetsBinding.instance.scheduleFrame();
    }

    if (deleted) {
      _clearLocalData(container, uid);
      await signOutToLogin(
        (alerts) => alerts.showSuccess(
          message:
              usedApple
                  ? 'settings_delete_account_done_apple'.tr()
                  : 'settings_delete_account_done'.tr(),
        ),
      );
      return;
    }

    switch (container.read(accountDeletionProvider).failure) {
      case DeletionSessionExpired():
        await signOutToLogin(
          (alerts) => alerts.showError(
            message: 'settings_delete_account_session_expired'.tr(),
          ),
        );
      case DeletionPartial():
        alerts.showError(
          message: 'settings_delete_account_error_partial'.tr(
            namedArgs: {'email': LegalLinks.supportEmail},
          ),
        );
      case DeletionNothingDeleted() || null:
        alerts.showError(message: 'settings_delete_account_error'.tr());
    }
  }

  static bool _usedApple(Map<String, dynamic>? appMetadata) {
    final providers = appMetadata?['providers'];
    return providers is List && providers.contains('apple');
  }

  /// Borra las claves locales que llevan el id del usuario (caché de Home,
  /// informe semanal, diagnóstico).
  static void _clearLocalData(ProviderContainer container, String? uid) {
    if (uid == null || uid.isEmpty) return;
    try {
      final prefs = container.read(sharedPreferencesProvider);
      for (final key in prefs.getKeys().toList()) {
        if (key.contains(uid)) prefs.remove(key);
      }
    } catch (_) {
      // Sin SharedPreferences no hay nada que limpiar.
    }
  }

  static Future<void> _signOutLocal(SupabaseAuthService auth) async {
    try {
      await auth.signOutLocal();
    } catch (_) {
      // El usuario ya no existe en el servidor; la sesión local vence sola.
    }
  }
}

/// El aviso va arriba del botón, con texto de peso normal, y el link abre la
/// tienda sin cerrar la hoja.
class _SubscriptionNotice extends StatelessWidget {
  const _SubscriptionNotice({required this.notice, required this.onOpenStore});

  final DeletionStoreNotice notice;
  final Future<void> Function(Uri) onOpenStore;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final store = notice.storeName;
    final url = notice.manageUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          store == null
              ? 'settings_delete_account_subscription_warning_generic'.tr()
              : 'settings_delete_account_subscription_warning'.tr(
                namedArgs: {'store': store},
              ),
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
        ),
        if (store != null && url != null)
          SizedBox(
            height: AppDimens.touchTarget,
            child: TextButton(
              onPressed: () => onOpenStore(url),
              style: TextButton.styleFrom(foregroundColor: colors.accentBlue),
              child: Text(
                'settings_delete_account_manage_subscription'.tr(
                  namedArgs: {'store': store},
                ),
                style: tt.titleSmall?.copyWith(
                  color: colors.accentBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Progreso que no se puede descartar mientras la función borra.
class _DeletingSheet extends StatelessWidget {
  const _DeletingSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return PopScope(
      canPop: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.sp24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // PortyLoader se expande: necesita alto acotado en la hoja.
              const SizedBox(height: 96, child: PortyLoader(size: 72)),
              const SizedBox(height: AppDimens.sp12),
              Text(
                'settings_delete_account_in_progress'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

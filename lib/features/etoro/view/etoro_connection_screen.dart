import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/etoro/nav/etoro_router.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/etoro/view/etoro_messages.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_disconnect_sheet.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_sync_note.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

/// Ajustes → eToro (también desde la Home vacía y el onboarding). Una sola
/// pantalla para los cuatro estados:
/// - sin conectar: qué hace y qué no hace Porty con la cuenta, y "Conectar";
/// - conectada: última sincronización, qué se importó, sincronizar ahora y
///   desconectar;
/// - "Reconectá tu cuenta": eToro cerró el acceso, lo importado sigue;
/// - sincronizando: los valores en skeleton (no un spinner).
class EtoroConnectionScreen extends StatefulHookConsumerWidget {
  const EtoroConnectionScreen({super.key});

  @override
  ConsumerState<EtoroConnectionScreen> createState() =>
      _EtoroConnectionScreenState();
}

class _EtoroConnectionScreenState
    extends BaseStatefulWidget<EtoroConnectionScreen> {
  // Se empuja por encima del shell, que ya escucha las alertas globales.
  @override
  bool get subscribesToGlobalEvents => false;

  /// Error del último intento de conexión (se muestra bajo el botón).
  String? _connectError;

  /// Solo la primera vez que se abre con la conexión ya cargada se salta la
  /// entrada animada.
  late final bool _animateEntrance = !ref.read(etoroConnectionProvider).loaded;

  @override
  void initState() {
    super.initState();
    runAfterPostFrameCallback(() {
      ref.read(etoroConnectionProvider.notifier).load();
    });
  }

  Future<void> _connect() async {
    final haptics = PortyHapticsService.maybeOf(context);
    final tier = ref.read(subscriptionProvider).tier;
    if (!SubscriptionPolicy.allows(tier, PlanFeature.brokerSync)) {
      haptics?.lockedTap();
      await SubscriptionPaywallSheet.show(
        context,
        ref,
        reason: PaywallReason.brokerSync,
        source: 'etoro_connect',
      );
      return;
    }
    haptics?.selectionTap();
    setState(() => _connectError = null);
    final outcome = await ref.read(etoroConnectionProvider.notifier).connect();
    if (!mounted) return;
    switch (outcome) {
      case EtoroConnected(:final syncFailed):
        haptics?.brokerSynced();
        context.pushReplacementNamed(
          EtoroRouter.resultRouteName,
          queryParameters: {
            if (syncFailed) EtoroRouter.syncFailedParam: 'failed',
          },
        );
      case EtoroConnectCancelled():
        break;
      case EtoroConnectPlanRequired():
        await SubscriptionPaywallSheet.show(
          context,
          ref,
          reason: PaywallReason.brokerSync,
          source: 'etoro_connect',
        );
      case EtoroConnectFailed(:final reason):
        final message = EtoroMessages.connectError(reason);
        if (message != null) {
          haptics?.brokerFailed();
          setState(() => _connectError = message);
        }
    }
  }

  Future<void> _syncNow() async {
    final haptics = PortyHapticsService.maybeOf(context);
    haptics?.selectionTap();
    final notifier = ref.read(etoroConnectionProvider.notifier);
    await notifier.sync(userInitiated: true);
    if (!mounted) return;
    if (ref.read(etoroConnectionProvider).lastActionError != null) {
      haptics?.brokerFailed();
    } else {
      haptics?.brokerSynced();
    }
  }

  Future<void> _disconnect() async {
    final state = ref.read(etoroConnectionProvider);
    final keepAsManual = await EtoroDisconnectSheet.show(
      context,
      importedCount: state.connection.lastResult?.imported,
    );
    if (keepAsManual == null || !mounted) return;
    final ok = await ref
        .read(etoroConnectionProvider.notifier)
        .disconnect(keepAsManual: keepAsManual);
    if (!mounted) return;
    if (!ok) PortyHapticsService.maybeOf(context)?.brokerFailed();
  }

  @override
  Widget buildView(BuildContext context) {
    final state = ref.watch(etoroConnectionProvider);
    final connection = state.connection;
    final loading = !state.loaded;

    Widget enter(int order, Widget child) => FadeSlideIn(
      delay: Duration(milliseconds: 40 * order),
      skipAnimation: !_animateEntrance,
      child: child,
    );

    final children = <Widget>[
      enter(0, _Header(connection: connection, loading: loading)),
      const SizedBox(height: AppDimens.sectionGap),
    ];

    if (loading) {
      children.add(const _StatusCard.skeleton());
    } else if (connection.status == EtoroConnectionStatus.notConnected) {
      children.addAll([
        enter(1, const _ReadOnlyPoints()),
        const SizedBox(height: AppDimens.sectionGap),
        enter(
          2,
          _ConnectBlock(
            label:
                state.activity == EtoroActivity.connecting
                    ? 'etoro_connect_waiting'.tr()
                    : 'etoro_connect_cta'.tr(),
            onPressed: state.isBusy ? null : _connect,
            error: _connectError,
          ),
        ),
      ]);
    } else {
      children.addAll([
        if (connection.needsReconnect) ...[
          enter(
            1,
            _ConnectBlock(
              label:
                  state.activity == EtoroActivity.connecting
                      ? 'etoro_connect_waiting'.tr()
                      : 'etoro_reconnect_cta'.tr(),
              onPressed: state.isBusy ? null : _connect,
              error: _connectError,
            ),
          ),
          const SizedBox(height: AppDimens.sectionGap),
        ],
        enter(
          2,
          _StatusCard(
            connection: connection,
            syncing: state.isSyncing,
            onOpenResult:
                connection.lastResult == null
                    ? null
                    : () => context.pushNamed(EtoroRouter.resultRouteName),
          ),
        ),
        MotionAwareSize(
          duration: const Duration(milliseconds: 200),
          child:
              state.lastActionError == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                    padding: const EdgeInsets.only(top: AppDimens.sp12),
                    child: _InlineError(
                      EtoroMessages.syncError(state.lastActionError!),
                    ),
                  ),
        ),
        if (connection.isConnected) ...[
          const SizedBox(height: AppDimens.sp20),
          enter(
            3,
            _SecondaryButton(
              icon: Icons.sync_rounded,
              label:
                  state.isSyncing
                      ? 'etoro_syncing'.tr()
                      : 'etoro_sync_now'.tr(),
              onPressed: state.isBusy ? null : _syncNow,
            ),
          ),
        ],
        const SizedBox(height: AppDimens.sp8),
        enter(
          4,
          Center(
            child: TextButton(
              onPressed: state.isBusy ? null : _disconnect,
              style: TextButton.styleFrom(
                foregroundColor: context.customColors.loss,
                minimumSize: const Size(
                  AppDimens.touchTarget,
                  AppDimens.touchTarget,
                ),
                textStyle: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              child: Text(
                state.activity == EtoroActivity.disconnecting
                    ? 'etoro_disconnecting'.tr()
                    : 'etoro_disconnect'.tr(),
              ),
            ),
          ),
        ),
      ]);
    }

    return Scaffold(
      // El logo de eToro ya está en el encabezado: la barra va sin título.
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            0,
            AppDimens.pageHorizontal,
            AppDimens.sp48,
          ),
          children: children,
        ),
      ),
    );
  }
}

/// Porty ↔ eToro, el título y una línea que explica. El enlace del medio y
/// la cara de Porty cuentan el estado antes de leer.
class _Header extends StatelessWidget {
  const _Header({required this.connection, required this.loading});

  final EtoroConnection connection;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final (title, body, link) = switch (connection.status) {
      EtoroConnectionStatus.notConnected => (
        'etoro_intro_title'.tr(),
        'etoro_intro_body'.tr(),
        EtoroLinkState.idle,
      ),
      EtoroConnectionStatus.connected => (
        'etoro_connected_title'.tr(),
        'etoro_connected_body'.tr(),
        EtoroLinkState.linked,
      ),
      EtoroConnectionStatus.reconnectRequired => (
        'etoro_reconnect_title'.tr(),
        'etoro_reconnect_body'.tr(
          namedArgs: {
            'when':
                connection.lastSyncAt == null
                    ? '—'
                    : EtoroSyncTime.relative(connection.lastSyncAt!),
          },
        ),
        EtoroLinkState.broken,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mientras carga, Porty espera en reposo (sin adelantar el estado).
        EtoroPortyLockup(state: loading ? EtoroLinkState.idle : link),
        const SizedBox(height: AppDimens.sp24),
        Semantics(
          header: true,
          child: SkeletonText(
            loading ? null : title,
            placeholder: 'Conectá tu cuenta de eToro',
            style: tt.displaySmall?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.2,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        SkeletonText(
          loading ? null : body,
          placeholder: 'Porty trae tus posiciones y las mantiene al día.',
          style: tt.bodyMedium?.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// Las tres promesas en una card, como las filas de Ajustes: solo lectura,
/// se actualiza sola, se desconecta cuando quieras.
class _ReadOnlyPoints extends StatelessWidget {
  const _ReadOnlyPoints();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final points = [
      (
        Icons.lock_outline_rounded,
        'etoro_point_read_only_title'.tr(),
        'etoro_point_read_only_body'.tr(),
      ),
      (
        Icons.sync_rounded,
        'etoro_point_sync_title'.tr(),
        'etoro_point_sync_body'.tr(),
      ),
      (
        Icons.link_off_rounded,
        'etoro_point_disconnect_title'.tr(),
        'etoro_point_disconnect_body'.tr(),
      ),
    ];
    return _Card(
      child: Column(
        children: [
          for (final (i, (icon, title, body)) in points.indexed) ...[
            if (i > 0) _CardDivider(indent: 64, color: colors.border),
            _Point(icon: icon, title: title, body: body),
          ],
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.sp16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconBubble(icon: icon),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: tt.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El ícono en un círculo teñido de acento, como en Ajustes.
class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.accentBlue.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: colors.accentBlue),
    );
  }
}

/// Botón principal (tinta) + el error del último intento debajo, sin mover
/// el resto: el alto del error se anima con reduce motion respetado.
class _ConnectBlock extends StatelessWidget {
  const _ConnectBlock({
    required this.label,
    required this.onPressed,
    required this.error,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
      height: 1.45,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PositionPrimaryButton(label: label, onPressed: onPressed),
        MotionAwareSize(
          duration: const Duration(milliseconds: 200),
          child:
              error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                    padding: const EdgeInsets.only(top: AppDimens.sp12),
                    child: _InlineError(error!),
                  ),
        ),
        const SizedBox(height: AppDimens.sp12),
        Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppDimens.sp4),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              TextSpan(text: 'etoro_connect_footnote'.tr()),
            ],
          ),
          textAlign: TextAlign.center,
          style: style,
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: context.customColors.loss,
          height: 1.45,
        ),
      ),
    );
  }
}

/// Estado de una cuenta conectada: arriba "Conectada" (o "Sin acceso") y
/// la cifra de posiciones importadas en grande; abajo, filas de label +
/// valor. Mientras sincroniza, los valores van en skeleton (el pulso lento
/// de la app).
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required EtoroConnection this.connection,
    required this.syncing,
    required this.onOpenResult,
  });

  const _StatusCard.skeleton()
    : connection = null,
      syncing = true,
      onOpenResult = null;

  final EtoroConnection? connection;
  final bool syncing;
  final VoidCallback? onOpenResult;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final c = connection;
    final result = c?.lastResult;
    final showValues = c != null && !syncing;

    final rows = <Widget>[
      _StatusRow(
        label: 'etoro_status_last_sync'.tr(),
        value:
            !showValues
                ? null
                : c.lastSyncAt == null
                ? '—'
                : EtoroSyncTime.relative(c.lastSyncAt!),
        warning: showValues && c.lastSyncFailed,
      ),
      _StatusRow(
        label: 'etoro_status_closed_imported'.tr(),
        value: !showValues ? null : '${result?.closedImported ?? 0}',
      ),
      _StatusRow(
        label: 'etoro_status_not_imported'.tr(),
        value: !showValues ? null : '${result?.notImportedCount ?? 0}',
        onTap: showValues ? onOpenResult : null,
      ),
    ];

    final card = _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.sp16,
              AppDimens.sp16,
              AppDimens.sp16,
              AppDimens.sp12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c != null) _StatusPill(reconnect: c.needsReconnect),
                if (c != null) const SizedBox(height: AppDimens.sp16),
                Semantics(
                  container: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(
                        !showValues ? null : '${result?.imported ?? 0}',
                        placeholder: '00',
                        style: tt.displaySmall?.copyWith(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                          height: 1.1,
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: AppDimens.sp2),
                      Text(
                        'etoro_status_imported'.tr(),
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final row in rows) ...[
            _CardDivider(indent: AppDimens.sp16, color: colors.border),
            row,
          ],
        ],
      ),
    );

    if (c == null || syncing) {
      return SkeletonScope(
        semanticsLabel: syncing && c != null ? 'etoro_syncing'.tr() : null,
        child: card,
      );
    }
    return card;
  }
}

/// "● Conectada" en verde, o "● Sin acceso" en rojo si eToro cerró el
/// acceso.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.reconnect});

  final bool reconnect;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final (fg, bg, label) =
        reconnect
            ? (colors.loss, colors.lossContainer, 'etoro_status_no_access'.tr())
            : (
              colors.profit,
              colors.profitContainer,
              'etoro_settings_connected'.tr(),
            );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp8,
        vertical: AppDimens.sp4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppDimens.sp6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    this.onTap,
    this.warning = false,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;

  /// La última sincronización falló: el valor en color de pérdida.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp16,
        vertical: 14,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: tt.bodyMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppDimens.sp12),
          // Flexible: con letra grande el valor baja de línea en vez de
          // empujar la fila fuera de la pantalla.
          Flexible(
            flex: 2,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child:
                  value == null
                      ? SkeletonText(
                        null,
                        placeholder: 'hace 00 min',
                        style: tt.bodyMedium,
                      )
                      : Text(
                        value!,
                        textAlign: TextAlign.end,
                        style: tt.bodyMedium?.copyWith(
                          color: warning ? colors.loss : colors.textSecondary,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppDimens.sp4),
            Icon(
              Icons.chevron_right_rounded,
              size: AppDimens.iconMd,
              color: colors.textSecondary,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () {
          PortyHapticsService.maybeOf(context)?.selectionTap();
          onTap!();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: row,
        ),
      ),
    );
  }
}

/// La card de la app: blanca, borde fino, radio grande.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider({required this.indent, required this.color});

  final double indent;
  final Color color;

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: indent,
    endIndent: AppDimens.sp16,
    color: color,
  );
}

/// Secundario: borde, sin relleno (como "Cerrar posición").
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: AppDimens.iconMd),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          backgroundColor: colors.surfaceCard,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

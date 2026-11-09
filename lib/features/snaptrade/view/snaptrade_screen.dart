import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/manual_positions/view/manual_positions_choice.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/binance/nav/binance_router.dart';
import 'package:portfolio_assistant/features/etoro/nav/etoro_router.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_sync_note.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';
import 'package:portfolio_assistant/features/snaptrade/view/widgets/snaptrade_brand.dart';
import 'package:portfolio_assistant/features/statement_import/nav/statement_import_router.dart';
import 'package:portfolio_assistant/features/subscription/config/conversion_flags.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/confirm_sheet.dart';
import 'package:portfolio_assistant/features/broker_connect/view/widgets/broker_screen_kit.dart';

/// "Actualizar ahora" (Gold) se muestra recién cuando SnapTrade confirme
/// cuánto cuesta cada actualización manual (ver
/// docs/superpowers/research/2026-10-31-snaptrade-contact-email.md). El
/// servidor además la exige con SNAPTRADE_MANUAL_REFRESH=on.
const snaptradeManualRefreshEnabled = false;

/// Mensaje simple para un error de SnapTrade (nunca el código).
String snaptradeErrorMessage(String type) => switch (type) {
  'snaptrade_plan_required' => 'snaptrade_error_plan'.tr(),
  'snaptrade_connection_limit' => 'snaptrade_error_limit'.tr(),
  'snaptrade_reconnect_required' => 'snaptrade_error_reconnect'.tr(),
  'snaptrade_refresh_limit' => 'snaptrade_error_refresh_limit'.tr(),
  'snaptrade_rate_limited' || 'rate_limited' => 'snaptrade_error_rate'.tr(),
  'snaptrade_sync_in_progress' => 'snaptrade_error_busy'.tr(),
  'snaptrade_not_configured' => 'snaptrade_error_not_configured'.tr(),
  'network' => 'snaptrade_error_network'.tr(),
  _ => 'snaptrade_error_unavailable'.tr(),
};

/// Conectar brókers que Porty no conecta directo (IBKR, Schwab…) por el
/// portal de SnapTrade, de solo lectura. Arriba Porty ↔ "Tu bróker", el
/// título y una línea; abajo, según el estado, las promesas y el botón, o
/// lo importado con cada bróker y sus acciones.
class SnaptradeScreen extends ConsumerStatefulWidget {
  const SnaptradeScreen({super.key});

  @override
  ConsumerState<SnaptradeScreen> createState() => _SnaptradeScreenState();
}

class _SnaptradeScreenState extends ConsumerState<SnaptradeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(snaptradeProvider.notifier).load();
    });
  }

  void _paywall(PaywallReason reason, String source) =>
      SubscriptionPaywallSheet.show(
        context,
        ref,
        reason: reason,
        source: source,
      );

  void _screenshotExit(String surface) {
    ref.read(productEventsProvider).log(ProductEvent.nudgeTapped, {
      'surface': surface,
      'action': 'screenshot',
    });
    context.pushNamed(StatementImportRouter.routeName);
  }

  Future<void> _connect({String? reconnect}) async {
    final darkMode = Theme.of(context).brightness == Brightness.dark;
    // Antes de conectar: la Home recarga adentro de `connect` y, si era la
    // primera carga, la registra por acá.
    final method = ref.read(portfolioLoadMethodProvider.notifier)
      ..state = PortfolioLoadMethod.snaptrade;
    final ok = await ref
        .read(snaptradeProvider.notifier)
        .connect(darkMode: darkMode, reconnect: reconnect);
    if (!mounted) return;
    if (!ok && method.state == PortfolioLoadMethod.snaptrade) {
      method.state = null;
    }
    final error = ref.read(snaptradeProvider).errorType;
    ref.read(productEventsProvider).log(ProductEvent.brokerConnectResult, {
      'broker': 'snaptrade',
      'result':
          ok && error == null
              ? 'ok'
              : error == 'snaptrade_plan_required'
              ? 'plan_required'
              : error == 'snaptrade_connection_limit'
              ? 'limit'
              : error == null
              ? 'cancelled'
              : 'error',
    });
    if (ok && error == null) {
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'snaptrade_connected_toast'.tr());
      final imported = ref.read(snaptradeProvider).connection.imported;
      await ManualPositionsChoice.offer(
        context,
        ref,
        broker:
            imported.length == 1 ? imported.single.name : 'snaptrade_tile'.tr(),
      );
    } else if (error == 'snaptrade_plan_required') {
      _paywall(PaywallReason.brokerSync, PaywallSource.snaptradeConnect);
    } else if (error == 'snaptrade_connection_limit') {
      _paywall(PaywallReason.goldRequired, PaywallSource.snaptradeMulti);
    }
  }

  /// Otro bróker: Gold lo conecta; Premium con uno ya conectado ve Gold.
  void _addAnother(bool multiAllowed) {
    if (!multiAllowed) {
      _paywall(PaywallReason.goldRequired, PaywallSource.snaptradeMulti);
      return;
    }
    _connect();
  }

  Future<void> _refresh() async {
    final ok = await ref.read(snaptradeProvider.notifier).refresh();
    if (ok && mounted) {
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'snaptrade_refresh_toast'.tr());
    }
  }

  Future<void> _remove(SnaptradeBrokerage brokerage) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'snaptrade_remove_title'.tr(namedArgs: {'broker': brokerage.name}),
      body: 'snaptrade_remove_body'.tr(),
      confirmLabel: 'snaptrade_remove_confirm'.tr(),
    );
    if (!confirmed || !mounted) return;
    await ref.read(snaptradeProvider.notifier).remove(brokerage.id);
  }

  Future<void> _disconnect() async {
    final keep = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => BrokerDisconnectSheet(
            title: 'snaptrade_disconnect_title'.tr(),
            body: 'snaptrade_disconnect_body'.tr(),
            keepLabel: 'snaptrade_disconnect_keep'.tr(),
            deleteLabel: 'snaptrade_disconnect_delete'.tr(),
          ),
    );
    if (keep == null || !mounted) return;
    await ref.read(snaptradeProvider.notifier).disconnect(keepAsManual: keep);
  }

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(subscriptionProvider).tier;
    final allowed = SubscriptionPolicy.allows(tier, PlanFeature.brokerSync);
    final multi = SubscriptionPolicy.allows(tier, PlanFeature.multiBrokerSync);
    final canRefresh =
        snaptradeManualRefreshEnabled &&
        SubscriptionPolicy.allows(tier, PlanFeature.brokerManualRefresh);
    final state = ref.watch(snaptradeProvider);
    final connection = state.connection;
    final error =
        state.errorType == null
            ? null
            : snaptradeErrorMessage(state.errorType!);

    final Widget body;
    if (!state.loaded) {
      body = Center(child: PortyLoader(message: 'loader_one_moment'.tr()));
    } else {
      final children = <Widget>[
        _Header(connection: connection),
        const SizedBox(height: AppDimens.sectionGap),
      ];
      if (!connection.isConnected) {
        children.addAll([
          const _Promises(),
          const SizedBox(height: AppDimens.sp20),
          if (!allowed) ...[
            PositionPrimaryButton(
              label: 'snaptrade_see_plans'.tr(),
              onPressed:
                  () => _paywall(
                    PaywallReason.brokerSync,
                    PaywallSource.snaptradeConnect,
                  ),
            ),
            const SizedBox(height: AppDimens.sp12),
            BrokerFootnote('snaptrade_locked_note'.tr()),
            if (ref.watch(brokerScreenshotExitEnabledProvider).value ??
                false) ...[
              const SizedBox(height: AppDimens.sp8),
              BrokerScreenshotExit(
                label: 'snaptrade_screenshot_exit'.tr(),
                onPressed: () => _screenshotExit('broker_locked_snaptrade'),
              ),
            ],
          ] else ...[
            PositionPrimaryButton(
              label: 'snaptrade_connect_cta'.tr(),
              loading: state.activity == SnaptradeActivity.connecting,
              onPressed: _connect,
            ),
            if (error != null) ...[
              const SizedBox(height: AppDimens.sp12),
              BrokerInlineError(error),
            ],
            const SizedBox(height: AppDimens.sp12),
            BrokerFootnote(
              (multi ? 'snaptrade_plan_note_gold' : 'snaptrade_plan_note').tr(),
            ),
          ],
        ]);
      } else {
        children.addAll([
          _StatusCard(
            connection: connection,
            // Conectar también importa al volver del portal.
            syncing:
                state.isSyncing ||
                state.activity == SnaptradeActivity.connecting,
            onReconnect: state.busy ? null : (b) => _connect(reconnect: b.id),
            onRemove: state.busy ? null : _remove,
            onGoDirect:
                (broker) => context.pushNamed(
                  broker == 'binance'
                      ? BinanceRouter.routeName
                      : EtoroRouter.connectionRouteName,
                ),
          ),
          if (error != null) ...[
            const SizedBox(height: AppDimens.sp12),
            BrokerInlineError(error),
          ],
          ManualPositionsRow(
            broker:
                connection.imported.length == 1
                    ? connection.imported.single.name
                    : 'snaptrade_tile'.tr(),
          ),
          const SizedBox(height: AppDimens.sp20),
          BrokerSecondaryButton(
            icon: Icons.sync_rounded,
            label:
                state.isSyncing
                    ? 'snaptrade_syncing'.tr()
                    : 'snaptrade_sync_now'.tr(),
            onPressed:
                state.busy ? null : ref.read(snaptradeProvider.notifier).sync,
          ),
          if (canRefresh) ...[
            const SizedBox(height: AppDimens.sp12),
            BrokerSecondaryButton(
              icon: Icons.bolt_rounded,
              label: 'snaptrade_refresh_now'.tr(),
              onPressed: state.busy ? null : _refresh,
            ),
          ],
          const SizedBox(height: AppDimens.sp12),
          BrokerSecondaryButton(
            icon: Icons.add_rounded,
            label: 'snaptrade_add_another'.tr(),
            onPressed: state.busy ? null : () => _addAnother(multi),
          ),
          if (!multi) ...[
            const SizedBox(height: AppDimens.sp12),
            BrokerFootnote('snaptrade_add_another_gold'.tr()),
          ],
          const SizedBox(height: AppDimens.sp8),
          Center(
            child: TextButton(
              onPressed: state.busy ? null : _disconnect,
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
              child: Text('snaptrade_disconnect'.tr()),
            ),
          ),
        ]);
      }
      body = ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp48,
        ),
        children: children,
      );
    }

    return Scaffold(appBar: AppBar(), body: SafeArea(top: false, child: body));
  }
}

/// Porty ↔ "Tu bróker", el título y una línea que explica.
class _Header extends StatelessWidget {
  const _Header({required this.connection});

  final SnaptradeConnection connection;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final broken = connection.brokerages.any((b) => b.imported && b.disabled);
    final (title, body, link) = switch (connection.status) {
      SnaptradeStatus.notConnected || SnaptradeStatus.pending => (
        'snaptrade_intro_title'.tr(),
        'snaptrade_intro_body'.tr(),
        EtoroLinkState.idle,
      ),
      SnaptradeStatus.connected when broken => (
        'snaptrade_reconnect_title'.tr(),
        'snaptrade_reconnect_body'.tr(),
        EtoroLinkState.broken,
      ),
      SnaptradeStatus.connected => (
        'snaptrade_connected_title'.tr(),
        'snaptrade_connected_body'.tr(),
        EtoroLinkState.linked,
      ),
      SnaptradeStatus.reconnectRequired => (
        'snaptrade_reconnect_title'.tr(),
        'snaptrade_reconnect_all_body'.tr(),
        EtoroLinkState.broken,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PortyPartnerLockup(state: link, partner: const SnaptradeLogoTile()),
        const SizedBox(height: AppDimens.sp24),
        Semantics(
          header: true,
          child: Text(
            title,
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
        Text(
          body,
          style: tt.bodyMedium?.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// Las tres promesas: solo lectura, se actualiza sola, se desconecta
/// cuando quieras.
class _Promises extends StatelessWidget {
  const _Promises();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final points = [
      (
        Icons.lock_outline_rounded,
        'snaptrade_point_read_only_title'.tr(),
        'snaptrade_point_read_only_body'.tr(),
      ),
      (
        Icons.sync_rounded,
        'snaptrade_point_sync_title'.tr(),
        'snaptrade_point_sync_body'.tr(),
      ),
      (
        Icons.link_off_rounded,
        'snaptrade_point_disconnect_title'.tr(),
        'snaptrade_point_disconnect_body'.tr(),
      ),
    ];
    return BrokerCard(
      child: Column(
        children: [
          for (final (i, (icon, title, body)) in points.indexed) ...[
            if (i > 0) BrokerCardDivider(indent: 64, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(AppDimens.sp16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrokerBubble(
                    child: Icon(icon, size: 18, color: colors.onChip),
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(child: BrokerTitleBody(title: title, body: body)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lo importado: la cifra en grande, la última actualización, cada bróker
/// con su estado y acción, lo que no se importó y el aviso del precio de
/// compra estimado.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.connection,
    required this.syncing,
    required this.onReconnect,
    required this.onRemove,
    required this.onGoDirect,
  });

  final SnaptradeConnection connection;
  final bool syncing;
  final void Function(SnaptradeBrokerage)? onReconnect;
  final void Function(SnaptradeBrokerage)? onRemove;
  final ValueChanged<String> onGoDirect;

  String? _skippedLine(SnaptradeSyncResult result) {
    final cash = {
      for (final s in result.notImported)
        if (s.reason == 'cash') s.ticker,
    };
    final other = {
      for (final s in result.notImported)
        if (s.reason != 'cash') s.ticker,
    };
    final line = [
      if (cash.isNotEmpty) 'snaptrade_skipped_cash'.tr(),
      if (other.isNotEmpty)
        'snaptrade_skipped_other'.tr(namedArgs: {'assets': other.join(', ')}),
    ].join(' ');
    return line.isEmpty ? null : line;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    // Todo caído, o algún bróker importado que se cortó.
    final reconnectAll =
        connection.status == SnaptradeStatus.reconnectRequired ||
        connection.imported.any((b) => b.disabled);
    final result = connection.lastResult;
    final skipped = result == null ? null : _skippedLine(result);

    return BrokerCard(
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
                BrokerStatusPill(
                  warn: reconnectAll,
                  label:
                      reconnectAll
                          ? 'snaptrade_status_reconnect'.tr()
                          : 'snaptrade_status_connected'.tr(),
                ),
                const SizedBox(height: AppDimens.sp16),
                Text(
                  '${result?.imported ?? 0}',
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
                  (result?.imported == 1
                          ? 'snaptrade_status_imported_one'
                          : 'snaptrade_status_imported')
                      .tr(),
                  style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          BrokerCardDivider(indent: AppDimens.sp16, color: colors.border),
          BrokerStatusRow(
            label: 'snaptrade_status_last_sync'.tr(),
            value:
                syncing
                    ? 'snaptrade_syncing'.tr()
                    : connection.lastSyncAt == null
                    ? '—'
                    : EtoroSyncTime.relative(connection.lastSyncAt!),
          ),
          for (final b in connection.brokerages) ...[
            BrokerCardDivider(indent: AppDimens.sp16, color: colors.border),
            _BrokerageRow(
              brokerage: b,
              onReconnect: onReconnect,
              onRemove: onRemove,
              onGoDirect: onGoDirect,
            ),
          ],
          if (skipped != null) ...[
            BrokerCardDivider(indent: AppDimens.sp16, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(AppDimens.sp16),
              child: BrokerTitleBody(
                title: 'snaptrade_status_not_imported'.tr(),
                body: skipped,
              ),
            ),
          ],
          if (result != null && result.estimatedCost.isNotEmpty) ...[
            BrokerCardDivider(indent: AppDimens.sp16, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(AppDimens.sp16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: AppDimens.iconMd,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  Expanded(
                    child: Text(
                      'snaptrade_estimated_cost'.tr(
                        namedArgs: {'tickers': result.estimatedCost.join(', ')},
                      ),
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Un bróker: el nombre, su estado en una línea y la acción que
/// corresponde (reconectar si se cayó; si no, quitar).
class _BrokerageRow extends StatelessWidget {
  const _BrokerageRow({
    required this.brokerage,
    required this.onReconnect,
    required this.onRemove,
    required this.onGoDirect,
  });

  final SnaptradeBrokerage brokerage;
  final void Function(SnaptradeBrokerage)? onReconnect;
  final void Function(SnaptradeBrokerage)? onRemove;

  /// eToro o Binance importados por acá: conectarlos directo es gratis y
  /// trae más datos (al conectarlo, se quita de SnapTrade solo).
  final ValueChanged<String> onGoDirect;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final broken = brokerage.imported && brokerage.disabled;
    final direct = brokerage.imported ? brokerage.directBroker : null;
    final subtitle = switch (brokerage.reason) {
      'plan_limit' => 'snaptrade_broker_plan_limit'.tr(),
      'direct_connection' => 'snaptrade_broker_direct'.tr(),
      'trade_permissions' => 'snaptrade_broker_trade'.tr(),
      _ when broken => 'snaptrade_broker_broken'.tr(),
      _ when direct != null => 'snaptrade_broker_go_direct'.tr(),
      _ => 'snaptrade_broker_imported'.tr(),
    };
    final void Function(SnaptradeBrokerage)? goDirect =
        direct == null ? null : (_) => onGoDirect(direct);
    final (label, action, color) =
        broken
            ? ('snaptrade_reconnect_cta'.tr(), onReconnect, colors.accentBlue)
            : direct != null
            ? ('snaptrade_go_direct_cta'.tr(), goDirect, colors.accentBlue)
            : ('snaptrade_remove_cta'.tr(), onRemove, colors.textSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.sp16,
        AppDimens.sp8,
        AppDimens.sp4,
        AppDimens.sp8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brokerage.name,
                  style: tt.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: tt.bodySmall?.copyWith(
                    color: broken ? colors.loss : colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDimens.sp8),
          // Con tope: un texto largo (otro idioma) no empuja el nombre.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: TextButton(
              onPressed: action == null ? null : () => action(brokerage),
              style: TextButton.styleFrom(
                foregroundColor: color,
                minimumSize: const Size(
                  AppDimens.touchTarget,
                  AppDimens.touchTarget,
                ),
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

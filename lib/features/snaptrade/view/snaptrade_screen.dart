import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_sync_note.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';
import 'package:portfolio_assistant/features/snaptrade/view/widgets/snaptrade_brand.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/confirm_sheet.dart';

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

  void _paywall(PaywallReason reason) =>
      SubscriptionPaywallSheet.show(context, ref, reason: reason);

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
    if (ok && error == null) {
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'snaptrade_connected_toast'.tr());
    } else if (error == 'snaptrade_plan_required') {
      _paywall(PaywallReason.brokerSync);
    } else if (error == 'snaptrade_connection_limit') {
      _paywall(PaywallReason.goldRequired);
    }
  }

  /// Otro bróker: Gold lo conecta; Premium con uno ya conectado ve Gold.
  void _addAnother(bool multiAllowed) {
    if (!multiAllowed) {
      _paywall(PaywallReason.goldRequired);
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
      builder: (ctx) => const _DisconnectSheet(),
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
              onPressed: () => _paywall(PaywallReason.brokerSync),
            ),
            const SizedBox(height: AppDimens.sp12),
            _Footnote('snaptrade_locked_note'.tr()),
          ] else ...[
            PositionPrimaryButton(
              label: 'snaptrade_connect_cta'.tr(),
              loading: state.busy,
              onPressed: _connect,
            ),
            if (error != null) ...[
              const SizedBox(height: AppDimens.sp12),
              _InlineError(error),
            ],
            const SizedBox(height: AppDimens.sp12),
            _Footnote(
              (multi ? 'snaptrade_plan_note_gold' : 'snaptrade_plan_note').tr(),
            ),
          ],
        ]);
      } else {
        children.addAll([
          _StatusCard(
            connection: connection,
            syncing: state.busy,
            onReconnect: state.busy ? null : (b) => _connect(reconnect: b.id),
            onRemove: state.busy ? null : _remove,
          ),
          if (error != null) ...[
            const SizedBox(height: AppDimens.sp12),
            _InlineError(error),
          ],
          const SizedBox(height: AppDimens.sp20),
          _SecondaryButton(
            icon: Icons.sync_rounded,
            label:
                state.busy
                    ? 'snaptrade_syncing'.tr()
                    : 'snaptrade_sync_now'.tr(),
            onPressed:
                state.busy ? null : ref.read(snaptradeProvider.notifier).sync,
          ),
          if (canRefresh) ...[
            const SizedBox(height: AppDimens.sp12),
            _SecondaryButton(
              icon: Icons.bolt_rounded,
              label: 'snaptrade_refresh_now'.tr(),
              onPressed: state.busy ? null : _refresh,
            ),
          ],
          const SizedBox(height: AppDimens.sp12),
          _SecondaryButton(
            icon: Icons.add_rounded,
            label: 'snaptrade_add_another'.tr(),
            onPressed: state.busy ? null : () => _addAnother(multi),
          ),
          if (!multi) ...[
            const SizedBox(height: AppDimens.sp12),
            _Footnote('snaptrade_add_another_gold'.tr()),
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
    return _Card(
      child: Column(
        children: [
          for (final (i, (icon, title, body)) in points.indexed) ...[
            if (i > 0) _CardDivider(indent: 64, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(AppDimens.sp16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bubble(child: Icon(icon, size: 18, color: colors.onChip)),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(child: _TitleBody(title: title, body: body)),
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
  });

  final SnaptradeConnection connection;
  final bool syncing;
  final void Function(SnaptradeBrokerage)? onReconnect;
  final void Function(SnaptradeBrokerage)? onRemove;

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

    return _Card(
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
                _StatusPill(
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
          _CardDivider(indent: AppDimens.sp16, color: colors.border),
          _StatusRow(
            label: 'snaptrade_status_last_sync'.tr(),
            value:
                syncing
                    ? 'snaptrade_syncing'.tr()
                    : connection.lastSyncAt == null
                    ? '—'
                    : EtoroSyncTime.relative(connection.lastSyncAt!),
          ),
          for (final b in connection.brokerages) ...[
            _CardDivider(indent: AppDimens.sp16, color: colors.border),
            _BrokerageRow(
              brokerage: b,
              onReconnect: onReconnect,
              onRemove: onRemove,
            ),
          ],
          if (skipped != null) ...[
            _CardDivider(indent: AppDimens.sp16, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(AppDimens.sp16),
              child: _TitleBody(
                title: 'snaptrade_status_not_imported'.tr(),
                body: skipped,
              ),
            ),
          ],
          if (result != null && result.estimatedCost.isNotEmpty) ...[
            _CardDivider(indent: AppDimens.sp16, color: colors.border),
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
  });

  final SnaptradeBrokerage brokerage;
  final void Function(SnaptradeBrokerage)? onReconnect;
  final void Function(SnaptradeBrokerage)? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final broken = brokerage.imported && brokerage.disabled;
    final subtitle = switch (brokerage.reason) {
      'plan_limit' => 'snaptrade_broker_plan_limit'.tr(),
      'direct_connection' => 'snaptrade_broker_direct'.tr(),
      'trade_permissions' => 'snaptrade_broker_trade'.tr(),
      _ when broken => 'snaptrade_broker_broken'.tr(),
      _ => 'snaptrade_broker_imported'.tr(),
    };
    final (label, action, color) =
        broken
            ? ('snaptrade_reconnect_cta'.tr(), onReconnect, colors.accentBlue)
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.warn, required this.label});

  final bool warn;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final (fg, bg) =
        warn
            ? (colors.loss, colors.lossContainer)
            : (colors.profit, colors.profitContainer);
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
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
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
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBody extends StatelessWidget {
  const _TitleBody({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
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
    );
  }
}

/// Un círculo teñido con un ícono, como en Ajustes.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.customColors.chip,
      shape: BoxShape.circle,
    ),
    child: child,
  );
}

/// Una línea chica con un candado, centrada (privacidad, plan).
class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Text.rich(
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
          TextSpan(text: text),
        ],
      ),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: colors.textSecondary,
        height: 1.45,
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
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

/// Secundario: borde, sin relleno (como en eToro y Binance).
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

class _DisconnectSheet extends StatelessWidget {
  const _DisconnectSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'snaptrade_disconnect_title'.tr(),
              style: tt.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              'snaptrade_disconnect_body'.tr(),
              style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppDimens.sp20),
            PositionPrimaryButton(
              label: 'snaptrade_disconnect_keep'.tr(),
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppDimens.sp8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.loss,
                  side: BorderSide(color: colors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  ),
                ),
                child: Text('snaptrade_disconnect_delete'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

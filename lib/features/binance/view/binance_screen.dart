import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/binance/view/widgets/binance_brand.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_sync_note.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';

/// Mensaje simple para un error de Binance (nunca el código).
String binanceErrorMessage(String type) => switch (type) {
  'binance_write_permissions' => 'binance_error_write'.tr(),
  'binance_no_read' => 'binance_error_no_read'.tr(),
  'binance_invalid_key' ||
  'binance_reconnect_required' => 'binance_error_invalid_key'.tr(),
  'binance_plan_required' => 'binance_error_plan'.tr(),
  'binance_region_blocked' => 'binance_error_region'.tr(),
  'binance_rate_limited' || 'rate_limited' => 'binance_error_rate'.tr(),
  'binance_sync_in_progress' => 'binance_error_busy'.tr(),
  'network' => 'binance_error_network'.tr(),
  _ => 'binance_error_unavailable'.tr(),
};

/// Conectar Binance con una clave de API de solo lectura, ver qué se
/// importó y desconectar. Mismo armado que eToro: arriba Porty ↔ Binance
/// (el enlace y la cara cuentan el estado), el título y una línea; abajo,
/// según el estado, las promesas y cómo crear la clave, o la card de lo
/// importado con sus acciones.
class BinanceScreen extends ConsumerStatefulWidget {
  const BinanceScreen({super.key});

  @override
  ConsumerState<BinanceScreen> createState() => _BinanceScreenState();
}

class _BinanceScreenState extends ConsumerState<BinanceScreen> {
  final _key = TextEditingController();
  final _secret = TextEditingController();
  bool _showSecret = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(binanceProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    final ok = await ref
        .read(binanceProvider.notifier)
        .connect(apiKey: _key.text, apiSecret: _secret.text);
    if (!mounted) return;
    if (ok) {
      _key.clear();
      _secret.clear();
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'binance_connected_toast'.tr());
    } else if (ref.read(binanceProvider).errorType == 'binance_plan_required') {
      _paywall();
    }
  }

  void _paywall() => SubscriptionPaywallSheet.show(
    context,
    ref,
    reason: PaywallReason.brokerSync,
  );

  Future<void> _disconnect() async {
    final keep = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => const _DisconnectSheet(),
    );
    if (keep == null || !mounted) return;
    await ref.read(binanceProvider.notifier).disconnect(keepAsManual: keep);
  }

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(subscriptionProvider).tier;
    final allowed = SubscriptionPolicy.allows(tier, PlanFeature.brokerSync);
    final state = ref.watch(binanceProvider);
    final connection = state.connection;
    final reconnect = connection.status == BinanceStatus.reconnectRequired;
    final error =
        state.errorType == null ? null : binanceErrorMessage(state.errorType!);

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
          const SizedBox(height: AppDimens.sectionGap),
          if (!allowed) ...[
            PositionPrimaryButton(
              label: 'binance_see_plans'.tr(),
              onPressed: _paywall,
            ),
            const SizedBox(height: AppDimens.sp12),
            _Footnote('binance_locked_note'.tr()),
          ] else
            ..._keyForm(state: state, error: error, reconnect: false),
        ]);
      } else {
        children.addAll([
          _StatusCard(connection: connection, syncing: state.busy),
          if (error != null && !reconnect) ...[
            const SizedBox(height: AppDimens.sp12),
            _InlineError(error),
          ],
          if (reconnect) ...[
            const SizedBox(height: AppDimens.sectionGap),
            ..._keyForm(state: state, error: error, reconnect: true),
          ] else ...[
            const SizedBox(height: AppDimens.sp20),
            _SecondaryButton(
              icon: Icons.sync_rounded,
              label:
                  state.busy ? 'binance_syncing'.tr() : 'binance_sync_now'.tr(),
              onPressed:
                  state.busy ? null : ref.read(binanceProvider.notifier).sync,
            ),
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
              child: Text('binance_disconnect'.tr()),
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

    return Scaffold(
      // El logo de Binance ya está en el encabezado: la barra va sin título.
      appBar: AppBar(),
      body: SafeArea(top: false, child: body),
    );
  }

  /// Cómo crear la clave, la clave y el secreto en su card, el botón y el
  /// error del intento (debajo, sin mover el resto).
  List<Widget> _keyForm({
    required BinanceState state,
    required String? error,
    required bool reconnect,
  }) {
    final colors = context.customColors;
    return [
      const _Steps(),
      const SizedBox(height: AppDimens.sp16),
      _Card(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.sp16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'binance_key_card_title'.tr(),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimens.sp12),
              TextField(
                controller: _key,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'binance_api_key'.tr(),
                  prefixIcon: const Icon(Icons.key_rounded),
                ),
              ),
              const SizedBox(height: AppDimens.sp12),
              TextField(
                controller: _secret,
                autocorrect: false,
                enableSuggestions: false,
                obscureText: !_showSecret,
                decoration: InputDecoration(
                  labelText: 'binance_api_secret'.tr(),
                  prefixIcon: const Icon(Icons.password_rounded),
                  suffixIcon: IconButton(
                    tooltip:
                        (_showSecret
                                ? 'binance_hide_secret'
                                : 'binance_show_secret')
                            .tr(),
                    icon: Icon(
                      _showSecret
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppDimens.sp20),
      PositionPrimaryButton(
        label:
            (reconnect ? 'binance_reconnect_cta' : 'binance_connect_cta').tr(),
        loading: state.busy,
        onPressed: _connect,
      ),
      if (error != null) ...[
        const SizedBox(height: AppDimens.sp12),
        _InlineError(error),
      ],
      const SizedBox(height: AppDimens.sp12),
      _Footnote('binance_privacy'.tr()),
    ];
  }
}

/// Porty ↔ Binance, el título y una línea que explica.
class _Header extends StatelessWidget {
  const _Header({required this.connection});

  final BinanceConnection connection;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final (title, body, link) = switch (connection.status) {
      BinanceStatus.notConnected => (
        'binance_intro_title'.tr(),
        'binance_intro_body'.tr(),
        EtoroLinkState.idle,
      ),
      BinanceStatus.connected => (
        'binance_connected_title'.tr(),
        'binance_connected_body'.tr(),
        EtoroLinkState.linked,
      ),
      BinanceStatus.reconnectRequired => (
        'binance_reconnect_title'.tr(),
        'binance_reconnect_body'.tr(),
        EtoroLinkState.broken,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PortyPartnerLockup(state: link, partner: const BinanceLogoTile()),
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
        'binance_point_read_only_title'.tr(),
        'binance_point_read_only_body'.tr(),
      ),
      (
        Icons.sync_rounded,
        'binance_point_sync_title'.tr(),
        'binance_point_sync_body'.tr(),
      ),
      (
        Icons.link_off_rounded,
        'binance_point_disconnect_title'.tr(),
        'binance_point_disconnect_body'.tr(),
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

/// Cómo crear la clave en Binance, paso a paso, con el número en un
/// círculo. El paso de los permisos se marca: es donde más se equivoca.
class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    const steps = [
      'binance_step_1',
      'binance_step_2',
      'binance_step_3',
      'binance_step_4',
    ];
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.sp16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'binance_steps_title'.tr(),
              style: tt.titleSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppDimens.sp16),
            for (final (i, key) in steps.indexed) ...[
              if (i > 0) const SizedBox(height: AppDimens.sp12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bubble(
                    size: 26,
                    child: Text(
                      '${i + 1}',
                      style: tt.labelMedium?.copyWith(
                        color: colors.onChip,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        key.tr(),
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          height: 1.45,
                          fontWeight: i == 2 ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lo importado: arriba el estado ("● Conectada · clave …1234") y la cifra
/// de criptos en grande; abajo, la última actualización, lo que no se
/// importó y, si hizo falta, el aviso del precio de compra estimado.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.connection, required this.syncing});

  final BinanceConnection connection;
  final bool syncing;

  String? _skippedLine(BinanceSyncResult result) {
    final cash = [
      for (final s in result.notImported)
        if (s.reason == 'cash') s.asset,
    ];
    final other = [
      for (final s in result.notImported)
        if (s.reason != 'cash') s.asset,
    ];
    final line = [
      if (cash.isNotEmpty)
        'binance_skipped_cash'.tr(namedArgs: {'assets': cash.join(', ')}),
      if (other.isNotEmpty)
        'binance_skipped_other'.tr(namedArgs: {'assets': other.join(', ')}),
    ].join(' ');
    return line.isEmpty ? null : line;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final reconnect = connection.status == BinanceStatus.reconnectRequired;
    final result = connection.lastResult;
    final skipped = result == null ? null : _skippedLine(result);
    final hint = connection.apiKeyHint;

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
                  reconnect: reconnect,
                  label:
                      reconnect
                          ? 'binance_status_reconnect'.tr()
                          : hint == null
                          ? 'binance_status_connected'.tr()
                          : 'binance_status_connected_hint'.tr(
                            namedArgs: {'hint': hint},
                          ),
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
                          ? 'binance_status_imported_one'
                          : 'binance_status_imported')
                      .tr(),
                  style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          _CardDivider(indent: AppDimens.sp16, color: colors.border),
          _StatusRow(
            label: 'binance_status_last_sync'.tr(),
            value:
                syncing
                    ? 'binance_syncing'.tr()
                    : connection.lastSyncAt == null
                    ? '—'
                    : EtoroSyncTime.relative(connection.lastSyncAt!),
          ),
          if (skipped != null) ...[
            _CardDivider(indent: AppDimens.sp16, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(AppDimens.sp16),
              child: _TitleBody(
                title: 'binance_status_not_imported'.tr(),
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
                      'binance_estimated_cost'.tr(
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.reconnect, required this.label});

  final bool reconnect;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final (fg, bg) =
        reconnect
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

/// Un círculo teñido con un ícono o un número, como en Ajustes.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.child, this.size = 36});

  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
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

/// Secundario: borde, sin relleno (como en eToro).
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
              'binance_disconnect_title'.tr(),
              style: tt.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              'binance_disconnect_body'.tr(),
              style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppDimens.sp20),
            PositionPrimaryButton(
              label: 'binance_disconnect_keep'.tr(),
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
                child: Text('binance_disconnect_delete'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

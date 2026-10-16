import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/binance/view/widgets/binance_source_badge.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_sync_note.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

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
/// importó y desconectar.
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
    final showForm =
        !connection.isConnected ||
        connection.status == BinanceStatus.reconnectRequired;

    return Scaffold(
      appBar: AppBar(title: Text('binance_title'.tr())),
      body: SafeArea(
        top: false,
        child:
            !state.loaded
                ? const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
                : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.pageHorizontal,
                    AppDimens.sp8,
                    AppDimens.pageHorizontal,
                    AppDimens.sp32,
                  ),
                  children: [
                    if (connection.isConnected)
                      _Status(
                        connection: connection,
                        busy: state.busy,
                        onSync: ref.read(binanceProvider.notifier).sync,
                        onDisconnect: _disconnect,
                      )
                    else
                      const _Intro(),
                    if (state.errorType != null) ...[
                      const SizedBox(height: AppDimens.sp16),
                      Semantics(
                        liveRegion: true,
                        child: _Notice(
                          icon: Icons.error_outline_rounded,
                          text: binanceErrorMessage(state.errorType!),
                        ),
                      ),
                    ],
                    if (showForm) ...[
                      const SizedBox(height: AppDimens.sp24),
                      if (!allowed)
                        PositionPrimaryButton(
                          label: 'binance_see_plans'.tr(),
                          onPressed: _paywall,
                        )
                      else ...[
                        const _Steps(),
                        const SizedBox(height: AppDimens.sp20),
                        TextField(
                          controller: _key,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'binance_api_key'.tr(),
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
                              onPressed:
                                  () => setState(
                                    () => _showSecret = !_showSecret,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppDimens.sp20),
                        PositionPrimaryButton(
                          label:
                              connection.isConnected
                                  ? 'binance_reconnect_cta'.tr()
                                  : 'binance_connect_cta'.tr(),
                          loading: state.busy,
                          onPressed: _connect,
                        ),
                        const SizedBox(height: AppDimens.sp12),
                        Text(
                          'binance_privacy'.tr(),
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: context.customColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BinanceSourceBadge(large: true),
        const SizedBox(height: AppDimens.sp16),
        Semantics(
          header: true,
          child: Text(
            'binance_intro_title'.tr(),
            style: tt.headlineSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          'binance_intro_body'.tr(),
          style: tt.bodyLarge?.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.all(AppDimens.cardPadding),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
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
          const SizedBox(height: AppDimens.sp12),
          for (final (i, key) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppDimens.sp8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}.',
                      style: tt.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      key.tr(),
                      style: tt.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.connection,
    required this.busy,
    required this.onSync,
    required this.onDisconnect,
  });

  final BinanceConnection connection;
  final bool busy;
  final VoidCallback onSync;
  final VoidCallback onDisconnect;

  String _skippedLine(BinanceSyncResult result) {
    final cash = [
      for (final s in result.notImported)
        if (s.reason == 'cash') s.asset,
    ];
    final other = [
      for (final s in result.notImported)
        if (s.reason != 'cash') s.asset,
    ];
    return [
      if (cash.isNotEmpty)
        'binance_skipped_cash'.tr(namedArgs: {'assets': cash.join(', ')}),
      if (other.isNotEmpty)
        'binance_skipped_other'.tr(namedArgs: {'assets': other.join(', ')}),
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final result = connection.lastResult;
    final reconnect = connection.status == BinanceStatus.reconnectRequired;
    final skipped = result == null ? '' : _skippedLine(result);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const BinanceSourceBadge(large: true),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Text(
                reconnect
                    ? 'binance_status_reconnect'.tr()
                    : connection.apiKeyHint == null
                    ? 'binance_status_connected'.tr()
                    : 'binance_status_connected_hint'.tr(
                      namedArgs: {'hint': connection.apiKeyHint!},
                    ),
                style: tt.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.sp16),
        if (reconnect)
          _Notice(
            icon: Icons.link_off_rounded,
            text: 'binance_reconnect_body'.tr(),
          )
        else ...[
          if (connection.lastSyncAt != null)
            Text(
              'binance_last_sync'.tr(
                namedArgs: {
                  'when': EtoroSyncTime.relative(connection.lastSyncAt!),
                },
              ),
              style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          if (result != null) ...[
            const SizedBox(height: AppDimens.sp8),
            Text(
              result.imported == 1
                  ? 'binance_imported_one'.tr()
                  : 'binance_imported'.tr(
                    namedArgs: {'count': '${result.imported}'},
                  ),
              style: tt.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: AppDimens.sp8),
              Text(
                skipped,
                style: tt.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
            if (result.estimatedCost.isNotEmpty) ...[
              const SizedBox(height: AppDimens.sp12),
              _Notice(
                icon: Icons.info_outline_rounded,
                text: 'binance_estimated_cost'.tr(
                  namedArgs: {'tickers': result.estimatedCost.join(', ')},
                ),
              ),
            ],
          ],
          const SizedBox(height: AppDimens.sp20),
          PositionPrimaryButton(
            label: 'binance_sync_now'.tr(),
            loading: busy,
            onPressed: onSync,
          ),
        ],
        const SizedBox(height: AppDimens.sp8),
        Center(
          child: TextButton(
            onPressed: busy ? null : onDisconnect,
            child: Text('binance_disconnect'.tr()),
          ),
        ),
      ],
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

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      padding: const EdgeInsets.all(AppDimens.sp12),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppDimens.iconMd, color: colors.textSecondary),
          const SizedBox(width: AppDimens.sp8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

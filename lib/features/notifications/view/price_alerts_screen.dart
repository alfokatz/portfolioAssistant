import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';
import 'package:portfolio_assistant/features/notifications/providers/price_alerts_provider.dart';
import 'package:portfolio_assistant/features/notifications/view/create_price_alert_sheet.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_section_card.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Ajustes → Alertas de precio (y al tocar una alerta cumplida de un ticker
/// que no está en la cartera).
class PriceAlertsScreen extends StatefulHookConsumerWidget {
  const PriceAlertsScreen({super.key});

  @override
  ConsumerState<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends BaseStatefulWidget<PriceAlertsScreen> {
  @override
  bool get subscribesToGlobalEvents => false;

  @override
  void initState() {
    super.initState();
    runAfterPostFrameCallback(
      () => ref.read(priceAlertsProvider.notifier).load(),
    );
  }

  Future<void> _create() async {
    final symbol = await showDialog<String>(
      context: context,
      builder: (_) => const _TickerDialog(),
    );
    if (symbol == null || symbol.isEmpty || !mounted) return;
    await CreatePriceAlertSheet.show(context, ref, symbol: symbol);
  }

  Future<void> _actions(PriceAlert alert) async {
    final action = await showModalBottomSheet<_AlertAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _ActionsSheet(alert: alert),
    );
    if (action == null || !mounted) return;
    final notifier = ref.read(priceAlertsProvider.notifier);
    try {
      switch (action) {
        case _AlertAction.activate:
          await notifier.setActive(alert, active: true);
        case _AlertAction.pause:
          await notifier.setActive(alert, active: false);
        case _AlertAction.delete:
          await notifier.delete(alert);
      }
    } on PriceAlertLimitReached {
      if (!mounted) return;
      final tier = ref.read(subscriptionProvider).tier;
      if (tier == SubscriptionTier.gold) {
        ref
            .read(alertProvider.notifier)
            .showError(
              message: 'price_alert_error_limit'.tr(
                namedArgs: {'count': '${PlanMatrix.of(tier).priceAlertLimit}'},
              ),
            );
      } else {
        await SubscriptionPaywallSheet.show(
          context,
          ref,
          reason: PaywallReason.priceAlerts,
          source: 'price_alert_reactivate',
        );
      }
    } catch (_) {
      if (!mounted) return;
      ref
          .read(alertProvider.notifier)
          .showError(message: 'price_alert_error_network'.tr());
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final state = ref.watch(priceAlertsProvider);
    final tier = ref.watch(subscriptionProvider).tier;
    final limit = PlanMatrix.of(tier).priceAlertLimit;
    final colors = context.customColors;
    final text = Theme.of(context).textTheme;

    final active =
        state.alerts.where((a) => a.status == PriceAlertStatus.active).toList();
    final triggered =
        state.alerts
            .where((a) => a.status == PriceAlertStatus.triggered)
            .toList();
    final paused =
        state.alerts.where((a) => a.status == PriceAlertStatus.paused).toList();

    Widget section(String title, List<PriceAlert> alerts) => Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sectionGap),
      child: SettingsSectionCard(
        title: title,
        children: [
          for (var i = 0; i < alerts.length; i++) ...[
            if (i > 0) const SettingsDivider(),
            _AlertRow(alert: alerts[i], onTap: () => _actions(alerts[i])),
          ],
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text('price_alerts_title'.tr())),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: ref.read(priceAlertsProvider.notifier).load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              AppDimens.sp8,
              AppDimens.pageHorizontal,
              AppDimens.sp48,
            ),
            children: [
              Text(
                'price_alerts_usage'.tr(
                  namedArgs: {
                    'count': '${active.length}',
                    'limit': '$limit',
                  },
                ),
                style: text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: AppDimens.sp20),
              if (!state.loaded)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppDimens.sp32),
                    child: CircularProgressIndicator.adaptive(),
                  ),
                )
              else if (state.alerts.isEmpty)
                _EmptyState(failed: state.loadFailed)
              else ...[
                if (active.isNotEmpty)
                  section('price_alerts_section_active'.tr(), active),
                if (triggered.isNotEmpty)
                  section('price_alerts_section_triggered'.tr(), triggered),
                if (paused.isNotEmpty)
                  section('price_alerts_section_paused'.tr(), paused),
              ],
              const SizedBox(height: AppDimens.sp8),
              PositionPrimaryButton(
                label: 'price_alerts_new'.tr(),
                onPressed: state.loaded ? _create : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Sube a $750.00", "Baja 10% (a $162.00)".
String priceAlertConditionLabel(PriceAlert alert) {
  final threshold = AppNumberFormat.money(alert.thresholdPrice);
  return switch (alert.condition) {
    PriceAlertCondition.above => 'price_alert_label_above'.tr(
      namedArgs: {'price': threshold},
    ),
    PriceAlertCondition.below => 'price_alert_label_below'.tr(
      namedArgs: {'price': threshold},
    ),
    PriceAlertCondition.pctUp => 'price_alert_label_pct_up'.tr(
      namedArgs: {
        'pct': AppNumberFormat.percent(alert.target, decimals: 0, signed: false),
        'price': threshold,
      },
    ),
    PriceAlertCondition.pctDown => 'price_alert_label_pct_down'.tr(
      namedArgs: {
        'pct': AppNumberFormat.percent(alert.target, decimals: 0, signed: false),
        'price': threshold,
      },
    ),
  };
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.onTap});

  final PriceAlert alert;
  final VoidCallback onTap;

  String _status(BuildContext context) {
    switch (alert.status) {
      case PriceAlertStatus.triggered:
        final at = alert.triggeredAt;
        final price = alert.triggeredPrice;
        if (at == null || price == null) return 'price_alert_status_done'.tr();
        return 'price_alert_status_triggered'.tr(
          namedArgs: {
            'date': DateFormat.MMMd(context.locale.toString()).format(
              at.toLocal(),
            ),
            'price': AppNumberFormat.money(price),
          },
        );
      case PriceAlertStatus.paused:
        return alert.pausedByPlan
            ? 'price_alert_status_paused_plan'.tr()
            : 'price_alert_status_paused'.tr();
      case PriceAlertStatus.active:
        final last = alert.lastPrice;
        final base =
            last == null
                ? 'price_alert_status_waiting'.tr()
                : 'price_alert_status_last'.tr(
                  namedArgs: {'price': AppNumberFormat.money(last)},
                );
        return alert.repeatDaily
            ? '$base · ${'price_alert_status_repeats'.tr()}'
            : base;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final text = Theme.of(context).textTheme;
    final muted = alert.status != PriceAlertStatus.active;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.sp16,
            vertical: 14,
          ),
          child: Row(
            children: [
              Icon(
                alert.condition.isUp
                    ? Icons.north_east_rounded
                    : Icons.south_east_rounded,
                size: AppDimens.iconMd,
                color: muted ? colors.textSecondary : colors.accentBlue,
              ),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alert.symbol} · ${priceAlertConditionLabel(alert)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      _status(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.35,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AlertAction { activate, pause, delete }

class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.alert});

  final PriceAlert alert;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              0,
              AppDimens.pageHorizontal,
              AppDimens.sp8,
            ),
            child: Text(
              '${alert.symbol} · ${priceAlertConditionLabel(alert)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (alert.status != PriceAlertStatus.active)
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text(
                (alert.status == PriceAlertStatus.triggered
                        ? 'price_alert_action_rearm'
                        : 'price_alert_action_resume')
                    .tr(),
              ),
              onTap: () => Navigator.of(context).pop(_AlertAction.activate),
            ),
          if (alert.status == PriceAlertStatus.active)
            ListTile(
              leading: const Icon(Icons.pause_rounded),
              title: Text('price_alert_action_pause'.tr()),
              onTap: () => Navigator.of(context).pop(_AlertAction.pause),
            ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: colors.loss),
            title: Text(
              'price_alert_action_delete'.tr(),
              style: TextStyle(color: colors.loss),
            ),
            onTap: () => Navigator.of(context).pop(_AlertAction.delete),
          ),
          const SizedBox(height: AppDimens.sp8),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp24),
      child: Column(
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 40,
            color: colors.textSecondary,
          ),
          const SizedBox(height: AppDimens.sp12),
          Text(
            (failed ? 'price_alerts_load_error' : 'price_alerts_empty').tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pide el ticker para una alerta nueva (desde la lista).
class _TickerDialog extends StatefulWidget {
  const _TickerDialog();

  @override
  State<_TickerDialog> createState() => _TickerDialogState();
}

class _TickerDialogState extends State<_TickerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final symbol = _controller.text.trim().toUpperCase();
    if (RegExp(r'^[A-Z0-9.\-^=]{1,15}$').hasMatch(symbol)) {
      Navigator.of(context).pop(symbol);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('price_alerts_ticker_title'.tr()),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(hintText: 'price_alerts_ticker_hint'.tr()),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr()),
        ),
        TextButton(onPressed: _submit, child: Text('price_alerts_ticker_next'.tr())),
      ],
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert_form.dart';
import 'package:portfolio_assistant/features/notifications/providers/price_alerts_provider.dart';
import 'package:portfolio_assistant/features/notifications/view/push_permission_sheet.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// "Avisame si VOO sube a / baja a / se mueve X%". Se abre desde el detalle
/// de una posición y desde la lista de alertas.
class CreatePriceAlertSheet extends ConsumerStatefulWidget {
  const CreatePriceAlertSheet({
    super.key,
    required this.symbol,
    this.currentPrice,
  });

  final String symbol;
  final double? currentPrice;

  /// Abre la hoja; si se creó la alerta, ofrece el permiso de
  /// notificaciones (el momento de más intención, plan §6). Devuelve la
  /// alerta creada o null.
  static Future<PriceAlert?> show(
    BuildContext context,
    WidgetRef ref, {
    required String symbol,
    double? currentPrice,
  }) async {
    final created = await showModalBottomSheet<PriceAlert>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => CreatePriceAlertSheet(
            symbol: symbol.toUpperCase(),
            currentPrice: currentPrice,
          ),
    );
    if (created == null || !context.mounted) return created;
    ref
        .read(alertProvider.notifier)
        .showSuccess(message: 'price_alert_created'.tr());
    await PushPermissionSheet.maybeShow(
      context,
      ref,
      reason: PushPromptReason.priceAlert,
    );
    return created;
  }

  @override
  ConsumerState<CreatePriceAlertSheet> createState() =>
      _CreatePriceAlertSheetState();
}

class _CreatePriceAlertSheetState extends ConsumerState<CreatePriceAlertSheet> {
  final _controller = TextEditingController();
  PriceAlertMode _mode = PriceAlertMode.above;
  bool _percentUp = false;
  bool _repeatDaily = false;
  double? _price;
  bool _loadingPrice = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _price = widget.currentPrice;
    if (_price == null) {
      _loadPrice();
    } else {
      _applySuggestion(5);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadPrice() async {
    setState(() => _loadingPrice = true);
    final result = await ref
        .read(quoteRepositoryProvider)
        .getCurrentPrice(widget.symbol);
    if (!mounted) return;
    setState(() {
      _loadingPrice = false;
      _price = result.fold((_) => null, (p) => p > 0 ? p : null);
    });
    if (_price != null && _controller.text.isEmpty) _applySuggestion(5);
  }

  void _applySuggestion(double pct) {
    final price = _price;
    setState(() {
      _error = null;
      if (_mode == PriceAlertMode.percent) {
        _controller.text = pct.abs().toStringAsFixed(0);
      } else if (price != null) {
        final signed = _mode == PriceAlertMode.above ? pct.abs() : -pct.abs();
        _controller.text = suggestedTarget(price, signed).toStringAsFixed(2);
      }
    });
  }

  void _setMode(PriceAlertMode mode) {
    if (mode == _mode) return;
    PortyHapticsService.maybeOf(context)?.selectionTap();
    setState(() => _mode = mode);
    _applySuggestion(5);
  }

  Future<void> _save() async {
    final built = buildPriceAlertDraft(
      symbol: widget.symbol,
      mode: _mode,
      input: _controller.text,
      percentUp: _percentUp,
      repeatDaily: _repeatDaily,
      currentPrice: _price,
    );
    if (built.error != null) {
      setState(() => _error = built.error!.key.tr());
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final alert = await ref
          .read(priceAlertsProvider.notifier)
          .create(built.draft!);
      if (!mounted) return;
      PortyHapticsService.maybeOf(context)?.selectionTap();
      Navigator.of(context).pop(alert);
    } on PriceAlertLimitReached catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final tier = ref.read(subscriptionProvider).tier;
      if (tier == SubscriptionTier.gold) {
        setState(
          () =>
              _error = 'price_alert_error_limit'.tr(
                namedArgs: {
                  'count':
                      '${e.limit ?? PlanMatrix.of(tier).priceAlertLimit}',
                },
              ),
        );
        return;
      }
      PortyHapticsService.maybeOf(context)?.lockedTap();
      await SubscriptionPaywallSheet.show(
        context,
        ref,
        reason: PaywallReason.priceAlerts,
        source: 'price_alert_limit',
      );
    } on PriceAlertFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            (e is PriceAlertInvalid
                    ? 'price_alert_error_invalid'
                    : 'price_alert_error_network')
                .tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final text = Theme.of(context).textTheme;
    final price = _price;
    final suggestions = switch (_mode) {
      PriceAlertMode.percent => const [5.0, 10.0, 20.0],
      _ => const [5.0, 10.0],
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
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
              Semantics(
                header: true,
                child: Text(
                  'price_alert_create_title'.tr(
                    namedArgs: {'ticker': widget.symbol},
                  ),
                  style: text.titleLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.sp4),
              Text(
                _loadingPrice
                    ? 'price_alert_loading_price'.tr()
                    : price == null
                    ? 'price_alert_no_price'.tr()
                    : 'price_alert_current_price'.tr(
                      namedArgs: {'price': AppNumberFormat.money(price)},
                    ),
                style: text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: AppDimens.sp20),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<PriceAlertMode>(
                  segments: [
                    ButtonSegment(
                      value: PriceAlertMode.above,
                      label: Text('price_alert_mode_above'.tr()),
                    ),
                    ButtonSegment(
                      value: PriceAlertMode.below,
                      label: Text('price_alert_mode_below'.tr()),
                    ),
                    ButtonSegment(
                      value: PriceAlertMode.percent,
                      label: Text('price_alert_mode_percent'.tr()),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setMode(s.first),
                ),
              ),
              const SizedBox(height: AppDimens.sp16),
              if (_mode == PriceAlertMode.percent) ...[
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text('price_alert_percent_down'.tr()),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('price_alert_percent_up'.tr()),
                      ),
                    ],
                    selected: {_percentUp},
                    showSelectedIcon: false,
                    onSelectionChanged:
                        (s) => setState(() {
                          _percentUp = s.first;
                          _error = null;
                        }),
                  ),
                ),
                const SizedBox(height: AppDimens.sp12),
              ],
              TextField(
                controller: _controller,
                autofocus: false,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                style: text.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: InputDecoration(
                  labelText:
                      (_mode == PriceAlertMode.percent
                              ? 'price_alert_percent_label'
                              : 'price_alert_price_label')
                          .tr(),
                  prefixText: _mode == PriceAlertMode.percent ? null : '\$ ',
                  suffixText: _mode == PriceAlertMode.percent ? '%' : null,
                  errorText: _error,
                  errorMaxLines: 3,
                ),
              ),
              if (price != null) ...[
                const SizedBox(height: AppDimens.sp12),
                Wrap(
                  spacing: AppDimens.sp8,
                  children: [
                    for (final pct in suggestions)
                      ActionChip(
                        label: Text(
                          _mode == PriceAlertMode.percent
                              ? '${pct.toStringAsFixed(0)}%'
                              : '${_mode == PriceAlertMode.above ? '+' : '-'}'
                                  '${pct.toStringAsFixed(0)}%',
                        ),
                        onPressed: () => _applySuggestion(pct),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppDimens.sp8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _repeatDaily,
                onChanged: (v) => setState(() => _repeatDaily = v),
                title: Text(
                  'price_alert_repeat'.tr(),
                  style: text.bodyLarge?.copyWith(color: colors.textPrimary),
                ),
                subtitle: Text(
                  'price_alert_repeat_desc'.tr(),
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(height: AppDimens.sp4),
              Text(
                'price_alert_delay_note'.tr(),
                style: text.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppDimens.sp20),
              PositionPrimaryButton(
                label: 'price_alert_create_cta'.tr(),
                loading: _saving,
                onPressed: _loadingPrice ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/display_currency/domain/fx_breakdown.dart';
import 'package:portfolio_assistant/features/display_currency/providers/display_currency_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/labeled_value_row.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

/// La etiqueta del total de la Home. En dólares (o sin tipo de cambio),
/// "Total". Con otra moneda, "Total en UYU ›": todos los números del
/// encabezado ya están en esa moneda y al tocarla se abre el desglose (de
/// dónde sale la ganancia: las inversiones o el tipo de cambio).
class DisplayTotalLabel extends ConsumerWidget {
  const DisplayTotalLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(displayMoneyProvider);
    final colors = context.customColors;
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: colors.textSecondary,
      letterSpacing: 0.3,
    );
    if (money.isUsd) return Text('portfolio_total_label'.tr(), style: style);
    final currency = money.currency;
    return Semantics(
      button: true,
      label: 'fx_total_semantics'.tr(
        namedArgs: {'currency': currency.labelKey.tr()},
      ),
      child: InkWell(
        onTap: () => FxBreakdownSheet.show(context),
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'fx_total_label'.tr(namedArgs: {'code': currency.code}),
                  style: style,
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: AppDimens.iconSm,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Tu cartera en pesos uruguayos": valor, costo y de dónde sale la
/// ganancia (las inversiones o el tipo de cambio).
class FxBreakdownSheet extends ConsumerWidget {
  const FxBreakdownSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const FxBreakdownSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(displayCurrencyProvider);
    final breakdown = ref.watch(fxBreakdownProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Porty dice cuánto movió el tipo de cambio (con el número), o
            // que no pudo traerlo; debajo, en qué moneda está viendo todo.
            _FxPortyHeader(
              currency: currency,
              data: breakdown.valueOrNull,
              loading: breakdown.isLoading,
              failed:
                  !breakdown.isLoading &&
                  (breakdown.hasError || breakdown.valueOrNull == null),
            ),
            const SizedBox(height: AppDimens.sp20),
            breakdown.when(
              loading: () => _Body(currency: currency, data: null),
              // Sin tipo de cambio lo dice Porty arriba.
              error: (_, __) => const SizedBox.shrink(),
              data:
                  (data) =>
                      data == null
                          ? const SizedBox.shrink()
                          : _Body(currency: currency, data: data),
            ),
          ],
        ),
      ),
    );
  }
}

class _FxPortyHeader extends StatelessWidget {
  const _FxPortyHeader({
    required this.currency,
    required this.data,
    required this.loading,
    required this.failed,
  });

  final DisplayCurrency currency;
  final FxBreakdown? data;
  final bool loading;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final where = 'fx_sheet_title'.tr(
      namedArgs: {'currency': currency.labelKey.tr().toLowerCase()},
    );
    final d = data;
    final (String key, String message, PortyAvatarState mood) =
        failed
            ? ('failed', 'fx_sheet_unavailable'.tr(), PortyAvatarState.error)
            : loading || d == null
            ? ('loading', where, PortyAvatarState.thinking)
            : d.currencyEffect > 0
            ? (
              'up',
              'fx_porty_up'.tr(
                namedArgs: {'amount': currency.money(d.currencyEffect)},
              ),
              PortyAvatarState.answered,
            )
            : d.currencyEffect < 0
            ? (
              'down',
              'fx_porty_down'.tr(
                namedArgs: {'amount': currency.money(-d.currencyEffect)},
              ),
              PortyAvatarState.serious,
            )
            : ('flat', 'fx_porty_flat'.tr(), PortyAvatarState.idle);
    return PortySays(
      messageKey: key,
      mood: mood,
      message: Semantics(
        header: true,
        child: Text(
          message,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
      footnote: key == 'loading' ? null : Text(where),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.currency, required this.data});

  final DisplayCurrency currency;

  /// `null` mientras carga (las filas muestran su skeleton).
  final FxBreakdown? data;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final d = data;
    String? m(double Function(FxBreakdown) pick) =>
        d == null ? null : currency.money(pick(d));
    String? signed(double Function(FxBreakdown) pick) =>
        d == null ? null : currency.signedMoney(pick(d));
    final rateFormat = NumberFormat.decimalPatternDigits(decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledValueRow(label: 'fx_sheet_value'.tr(), value: m((b) => b.value)),
        const SizedBox(height: AppDimens.sp12),
        LabeledValueRow(label: 'fx_sheet_cost'.tr(), value: m((b) => b.cost)),
        const SizedBox(height: AppDimens.sp12),
        LabeledValueRow(
          label: 'fx_sheet_gain'.tr(),
          value:
              d == null
                  ? null
                  : '${currency.signedMoney(d.gain)} '
                      '(${AppNumberFormat.percent(d.gainPercent)})',
          valueColor: d == null ? null : colors.pnlColor(d.gain),
        ),
        const SizedBox(height: AppDimens.sp20),
        Text(
          'fx_sheet_split_title'.tr(),
          style: tt.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppDimens.sp12),
        LabeledValueRow(
          label: 'fx_sheet_investments'.tr(),
          value: signed((b) => b.investmentEffect),
          valueColor: d == null ? null : colors.pnlColor(d.investmentEffect),
        ),
        const SizedBox(height: AppDimens.sp12),
        LabeledValueRow(
          label: 'fx_sheet_currency'.tr(),
          value: signed((b) => b.currencyEffect),
          valueColor: d == null ? null : colors.pnlColor(d.currencyEffect),
        ),
        const SizedBox(height: AppDimens.sp20),
        Text(
          d == null
              ? ''
              : 'fx_sheet_rate'.tr(
                namedArgs: {
                  'rate': rateFormat.format(d.rateNow),
                  'code': currency.code,
                },
              ),
          style: tt.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          [
            'fx_sheet_explainer'.tr(),
            if (currency == DisplayCurrency.ars) 'fx_sheet_ars_official'.tr(),
            if (d != null && d.lotsWithoutHistory > 0)
              'fx_sheet_missing_history'.tr(),
          ].join(' '),
          style: tt.bodySmall?.copyWith(
            color: colors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

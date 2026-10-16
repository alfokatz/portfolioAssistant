import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/display_currency/domain/fx_breakdown.dart';
import 'package:portfolio_assistant/features/display_currency/providers/display_currency_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/labeled_value_row.dart';

/// Debajo del total de la Home: "≈ $U 1.234.567". Solo si eligió otra
/// moneda y hay tipo de cambio. Al tocarla, el desglose.
class DisplayCurrencyLine extends ConsumerWidget {
  const DisplayCurrencyLine({super.key, required this.totalUsd});

  final double totalUsd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(displayCurrencyProvider);
    if (currency.isUsd) return const SizedBox.shrink();
    final rate = ref.watch(fxRateProvider(currency)).valueOrNull;
    if (rate == null) return const SizedBox.shrink();
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final amount = currency.money(totalUsd * rate);
    return Semantics(
      button: true,
      label: 'fx_line_semantics'.tr(
        namedArgs: {'amount': amount, 'currency': currency.labelKey.tr()},
      ),
      child: InkWell(
        onTap: () => FxBreakdownSheet.show(context),
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    '≈ $amount',
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
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
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
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
            Semantics(
              header: true,
              child: Text(
                'fx_sheet_title'.tr(
                  namedArgs: {'currency': currency.labelKey.tr().toLowerCase()},
                ),
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp16),
            breakdown.when(
              loading: () => _Body(currency: currency, data: null),
              error: (_, __) => _Unavailable(),
              data:
                  (data) =>
                      data == null
                          ? _Unavailable()
                          : _Body(currency: currency, data: data),
            ),
          ],
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Text(
    'fx_sheet_unavailable'.tr(),
    style: Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: context.customColors.textSecondary),
  );
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

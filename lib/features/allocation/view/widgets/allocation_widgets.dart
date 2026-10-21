import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';
import 'package:portfolio_assistant/shared/utils/user_number.dart';

/// Margen mínimo y máximo que se ofrece para el aviso (la base acepta 1–50).
const allocationMinThreshold = 2.0;
const allocationMaxThreshold = 15.0;

/// El color de un ticker del plan: el del puesto [index] en la paleta de
/// series del chat (los mismos tonos que la barra de "Tu portfolio").
Color allocationColor(BuildContext context, int index) {
  QaColors.resolve(Theme.of(context).brightness);
  return QaPalette.series(index);
}

final _pct0 = NumberFormat.decimalPatternDigits(decimalDigits: 0);

String allocationPct(double v) => '${_pct0.format(v)}%';

/// Una caja con borde, como las otras cards de la app. Material (no un
/// Container decorado): las filas con check o switch pintan su fondo y el
/// splash en el Material más cercano.
class AllocationCard extends StatelessWidget {
  const AllocationCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Material(
      color: colors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppDimens.cardPadding),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Título de una card, con una acción opcional a la derecha ("Cambiar").
class AllocationCardTitle extends StatelessWidget {
  const AllocationCardTitle(this.text, {super.key, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final action = this.action;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: tt.titleSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (action != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppDimens.touchTarget),
                padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp8),
              ),
              child: Text(action, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
    );
  }
}

/// Un tramo de la barra del plan.
typedef PlanSlice = ({String ticker, double pct, Color color});

/// Barra apilada: cómo se reparte el 100% entre los tickers.
class PlanBar extends StatelessWidget {
  const PlanBar({super.key, required this.slices, this.height = 12});

  final List<PlanSlice> slices;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final shown = [
      for (final s in slices)
        if (s.pct > 0) s,
    ];
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child:
              shown.isEmpty
                  ? ColoredBox(color: colors.track)
                  : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, s) in shown.indexed) ...[
                        if (i > 0) SizedBox(width: 2, height: height),
                        Expanded(
                          flex: (s.pct * 10).round().clamp(1, 1000),
                          child: ColoredBox(color: s.color),
                        ),
                      ],
                    ],
                  ),
        ),
      ),
    );
  }
}

/// Punto del color del ticker (el vínculo entre la barra y la fila).
class PlanDot extends StatelessWidget {
  const PlanDot(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Cómo quiere que Porty le avise: lo explica, deja elegir y muestra con
/// sus propios tickers qué significa el margen elegido.
class AlertSettingsEditor extends StatelessWidget {
  const AlertSettingsEditor({
    super.key,
    required this.threshold,
    required this.notify,
    required this.frequency,
    required this.targets,
    required this.currentPct,
    required this.onThreshold,
    required this.onNotify,
    required this.onFrequency,
  });

  final double threshold;
  final bool notify;
  final AllocationAlertFrequency frequency;

  /// Objetivos del plan (en %), en el orden del plan.
  final Map<String, double> targets;

  /// Peso de hoy de cada ticker que tiene (en %).
  final Map<String, double> currentPct;

  final ValueChanged<double> onThreshold;
  final ValueChanged<bool> onNotify;
  final ValueChanged<AllocationAlertFrequency> onFrequency;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final points = threshold.round();
    final level =
        points <= 3
            ? 'allocation_margin_tight'
            : points <= 7
            ? 'allocation_margin_balanced'
            : 'allocation_margin_wide';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AllocationCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AllocationCardTitle('allocation_margin_title'.tr()),
              const SizedBox(height: AppDimens.sp4),
              Text(
                'allocation_margin_body'.tr(),
                style: tt.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppDimens.sp16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      'allocation_margin_value'.tr(
                        namedArgs: {'points': '$points'},
                      ),
                      style: tt.headlineSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        level.tr(),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value:
                    threshold
                        .clamp(allocationMinThreshold, allocationMaxThreshold)
                        .toDouble(),
                min: allocationMinThreshold,
                max: allocationMaxThreshold,
                divisions:
                    (allocationMaxThreshold - allocationMinThreshold).round(),
                label: 'allocation_margin_value'.tr(
                  namedArgs: {'points': '$points'},
                ),
                activeColor: colors.accentBlue,
                inactiveColor: colors.track,
                onChanged: (v) {
                  if (v.round() != points) HapticFeedback.selectionClick();
                  onThreshold(v.roundToDouble());
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'allocation_margin_more_alerts'.tr(),
                      style: tt.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  Expanded(
                    child: Text(
                      'allocation_margin_fewer_alerts'.tr(),
                      textAlign: TextAlign.end,
                      style: tt.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (targets.isNotEmpty) ...[
                const SizedBox(height: AppDimens.sp16),
                Text(
                  'allocation_bands_title'.tr(),
                  style: tt.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppDimens.sp8),
                AlertBands(
                  threshold: threshold,
                  targets: targets,
                  currentPct: currentPct,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppDimens.sp12),
        // Material (no un Container decorado): el SwitchListTile pinta su
        // fondo y el splash en el Material más cercano.
        Material(
          color: colors.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            side: BorderSide(color: colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: notify,
                  onChanged: onNotify,
                  title: Text(
                    'allocation_notify'.tr(),
                    style: tt.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'allocation_notify_body'.tr(),
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ),
                if (notify) ...[
                  const SizedBox(height: AppDimens.sp12),
                  Text(
                    'allocation_frequency_title'.tr(),
                    style: tt.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp8),
                  SegmentedChoice<AllocationAlertFrequency>(
                    options: [
                      (
                        value: AllocationAlertFrequency.weekly,
                        label: 'allocation_frequency_weekly'.tr(),
                      ),
                      (
                        value: AllocationAlertFrequency.monthly,
                        label: 'allocation_frequency_monthly'.tr(),
                      ),
                    ],
                    selected: frequency,
                    onChanged: onFrequency,
                  ),
                  const SizedBox(height: AppDimens.sp8),
                  Text(
                    (frequency == AllocationAlertFrequency.weekly
                            ? 'allocation_frequency_weekly_body'
                            : 'allocation_frequency_monthly_body')
                        .tr(),
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Con el margen elegido, entre qué pesos está bien cada ticker y cómo
/// está hoy. Lo que tiene y no está en el plan, aparte.
class AlertBands extends StatelessWidget {
  const AlertBands({
    super.key,
    required this.threshold,
    required this.targets,
    required this.currentPct,
  });

  final double threshold;
  final Map<String, double> targets;
  final Map<String, double> currentPct;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final hasHoldings = currentPct.values.any((v) => v > 0);
    final outside = [
      for (final e in currentPct.entries)
        if (e.value > 0 && !targets.containsKey(e.key)) e,
    ]..sort((a, b) => b.value.compareTo(a.value));

    Widget line({
      required int colorIndex,
      required String ticker,
      required String range,
      double? today,
      required bool ok,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: PlanDot(
                colorIndex < 0
                    ? colors.textSecondary.withValues(alpha: 0.4)
                    : allocationColor(context, colorIndex),
              ),
            ),
            const SizedBox(width: AppDimens.sp8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$ticker  ',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: range),
                  ],
                ),
                style: tt.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            if (hasHoldings) ...[
              const SizedBox(width: AppDimens.sp8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  'allocation_bands_today'.tr(
                    namedArgs: {'pct': allocationPct(today ?? 0)},
                  ),
                  textAlign: TextAlign.end,
                  style: tt.bodySmall?.copyWith(
                    color: ok ? colors.textSecondary : colors.accentWarm,
                    fontWeight: ok ? FontWeight.w500 : FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.sp4),
              Icon(
                ok ? Icons.check_rounded : Icons.priority_high_rounded,
                size: AppDimens.iconSm,
                color: ok ? colors.profit : colors.accentWarm,
                semanticLabel:
                    (ok ? 'allocation_bands_ok' : 'allocation_bands_off').tr(),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final (i, e) in targets.entries.indexed)
          line(
            colorIndex: i,
            ticker: e.key,
            range:
                e.value - threshold <= 0
                    ? 'allocation_bands_range_top'.tr(
                      namedArgs: {'high': allocationPct(e.value + threshold)},
                    )
                    : 'allocation_bands_range'.tr(
                      namedArgs: {
                        'low': allocationPct(e.value - threshold),
                        'high': allocationPct(
                          (e.value + threshold).clamp(0, 100).toDouble(),
                        ),
                      },
                    ),
            today: currentPct[e.key] ?? 0,
            ok: ((currentPct[e.key] ?? 0) - e.value).abs() < threshold,
          ),
        for (final e in outside)
          line(
            colorIndex: -1,
            ticker: e.key,
            range: 'allocation_bands_range_outside'.tr(
              namedArgs: {'high': allocationPct(threshold)},
            ),
            today: e.value,
            ok: e.value < threshold,
          ),
      ],
    );
  }
}

/// "¿Cuánto vas a sumar?": cuánto poner en cada ticker para acercarse al
/// plan, sin vender nada, y cómo quedaría cada uno.
class ContributionSheet extends StatefulWidget {
  const ContributionSheet({
    super.key,
    required this.values,
    required this.targets,
    this.onAskPorty,
  });

  final Map<String, double> values;
  final Map<String, double> targets;

  /// Abre el chat con la pregunta (recibe el monto escrito).
  final ValueChanged<double>? onAskPorty;

  static Future<void> show(
    BuildContext context, {
    required Map<String, double> values,
    required Map<String, double> targets,
    ValueChanged<double>? onAskPorty,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (_) => ContributionSheet(
          values: values,
          targets: targets,
          onAskPorty: onAskPorty,
        ),
  );

  @override
  State<ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends State<ContributionSheet> {
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final amount = parseUserNumber(_amount.text) ?? 0;
    final split = AllocationMath.contribution(
      values: widget.values,
      targets: widget.targets,
      amount: amount,
    );
    final after = AllocationMath.weightsAfter(
      values: widget.values,
      split: split,
    );
    // El mismo orden (y colores) que el tablero: de mayor a menor objetivo.
    final order = [
      for (final r in AllocationMath.rows(
        values: widget.values,
        targets: widget.targets,
      ))
        if (r.targetPct > 0) r.ticker,
    ];
    final entries =
        split.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

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
              Text(
                'allocation_contribution_title'.tr(),
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimens.sp6),
              Text(
                'allocation_contribution_sheet_body'.tr(),
                style: tt.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppDimens.sp16),
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'allocation_contribution_amount'.tr(),
                  prefixText: '\$ ',
                ),
              ),
              if (entries.isNotEmpty) ...[
                const SizedBox(height: AppDimens.sp20),
                Text(
                  'allocation_contribution_result'.tr(),
                  style: tt.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppDimens.sp8),
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        PlanDot(
                          allocationColor(
                            context,
                            order.indexOf(e.key).clamp(0, 99),
                          ),
                        ),
                        const SizedBox(width: AppDimens.sp8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.key,
                                style: tt.bodyMedium?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'allocation_contribution_after'.tr(
                                  namedArgs: {
                                    'after': allocationPct(after[e.key] ?? 0),
                                    'target': allocationPct(
                                      widget.targets[e.key] ?? 0,
                                    ),
                                  },
                                ),
                                style: tt.bodySmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          AppNumberFormat.money(e.value),
                          style: tt.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppDimens.sp8),
                Text(
                  'allocation_contribution_note'.tr(),
                  style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: AppDimens.sp20),
              PositionPrimaryButton(
                label: 'allocation_contribution_done'.tr(),
                onPressed: () => Navigator.of(context).pop(),
              ),
              if (widget.onAskPorty != null && amount > 0)
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onAskPorty!(amount);
                    },
                    child: Text('allocation_contribution_ask_porty'.tr()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/allocation/providers/allocation_provider.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';
import 'package:portfolio_assistant/shared/utils/user_number.dart';

/// "Mi plan de cartera": cuánto quiere de cada ticker, cuánto se alejó y
/// cómo repartir el próximo aporte. Porty hace la cuenta del plan del
/// usuario; no recomienda qué comprar.
class AllocationScreen extends ConsumerStatefulWidget {
  const AllocationScreen({super.key});

  @override
  ConsumerState<AllocationScreen> createState() => _AllocationScreenState();
}

class _AllocationScreenState extends ConsumerState<AllocationScreen> {
  final _amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(allocationProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await ref.read(allocationProvider.notifier).save();
    if (!mounted) return;
    final error = ref.read(allocationProvider).error;
    if (ok) {
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'allocation_saved'.tr());
    } else if (error == AllocationError.locked) {
      SubscriptionPaywallSheet.show(
        context,
        ref,
        reason: PaywallReason.modeLocked,
      );
    } else if (error == AllocationError.unavailable) {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'allocation_error_save'.tr());
    }
  }

  Future<void> _editTarget({AllocationRow? row}) async {
    final result = await TargetSheet.show(
      context,
      ticker: row?.ticker,
      current: row?.targetPct,
    );
    if (result == null) return;
    ref
        .read(allocationProvider.notifier)
        .setTarget(result.ticker, result.percent);
  }

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(subscriptionProvider).tier;
    final allowed = SubscriptionPolicy.allows(tier, PlanFeature.allocationPlan);
    final state = ref.watch(allocationProvider);
    final values = ref.watch(goalHoldingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('allocation_title'.tr())),
      body: SafeArea(
        top: false,
        child:
            !allowed
                ? _Locked(
                  onSeePlans:
                      () => SubscriptionPaywallSheet.show(
                        context,
                        ref,
                        reason: PaywallReason.modeLocked,
                      ),
                )
                : !state.loaded
                ? const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
                : state.draft.isEmpty
                ? _Intro(
                  hasHoldings: values.isNotEmpty,
                  onStart:
                      () => ref
                          .read(allocationProvider.notifier)
                          .startFromCurrent(values),
                  onAdd: () => _editTarget(),
                )
                : _Editor(
                  state: state,
                  values: values,
                  amount: _amount,
                  onEdit: (row) => _editTarget(row: row),
                  onAdd: () => _editTarget(),
                  onSave: _save,
                ),
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.onSeePlans});

  final VoidCallback onSeePlans;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppDimens.pageHorizontal),
      children: [
        Text(
          'allocation_intro_title'.tr(),
          style: tt.headlineSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          'allocation_locked_body'.tr(),
          style: tt.bodyLarge?.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppDimens.sp24),
        PositionPrimaryButton(
          label: 'allocation_see_plans'.tr(),
          onPressed: onSeePlans,
        ),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.hasHoldings,
    required this.onStart,
    required this.onAdd,
  });

  final bool hasHoldings;
  final VoidCallback onStart;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppDimens.pageHorizontal),
      children: [
        Icon(Icons.donut_large_rounded, size: 40, color: colors.textSecondary),
        const SizedBox(height: AppDimens.sp16),
        Semantics(
          header: true,
          child: Text(
            'allocation_intro_title'.tr(),
            style: tt.headlineSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          'allocation_intro_body'.tr(),
          style: tt.bodyLarge?.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppDimens.sp24),
        PositionPrimaryButton(
          label: 'allocation_start_current'.tr(),
          onPressed: hasHoldings ? onStart : null,
        ),
        const SizedBox(height: AppDimens.sp8),
        TextButton(onPressed: onAdd, child: Text('allocation_add'.tr())),
        const SizedBox(height: AppDimens.sp16),
        Text(
          'allocation_disclaimer'.tr(),
          style: tt.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _Editor extends ConsumerWidget {
  const _Editor({
    required this.state,
    required this.values,
    required this.amount,
    required this.onEdit,
    required this.onAdd,
    required this.onSave,
  });

  final AllocationState state;
  final Map<String, double> values;
  final TextEditingController amount;
  final ValueChanged<AllocationRow> onEdit;
  final VoidCallback onAdd;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final notifier = ref.read(allocationProvider.notifier);
    final draft = state.draft;
    final rows = AllocationMath.rows(values: values, targets: draft.targets);
    final sum = draft.targetSum;
    final pct = NumberFormat.decimalPatternDigits(decimalDigits: 1);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              AppDimens.sp8,
              AppDimens.pageHorizontal,
              AppDimens.sp24,
            ),
            children: [
              Text(
                'allocation_editor_body'.tr(),
                style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppDimens.sp12),
              _SumLine(
                sum: sum,
                ok: draft.sumsTo100,
                onNormalize: notifier.normalize,
              ),
              const SizedBox(height: AppDimens.sp12),
              for (final row in rows)
                _RowTile(
                  row: row,
                  threshold: draft.driftThreshold,
                  onTap: () => onEdit(row),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: Text('allocation_add'.tr()),
                ),
              ),
              const SizedBox(height: AppDimens.sp16),
              _ContributionCard(
                amount: amount,
                values: values,
                targets: draft.sumsTo100 ? draft.targets : const {},
              ),
              const SizedBox(height: AppDimens.sp16),
              _AlertSettings(
                threshold: draft.driftThreshold,
                notify: draft.notify,
                onThreshold: notifier.setThreshold,
                onNotify: notifier.setNotify,
              ),
              const SizedBox(height: AppDimens.sp16),
              Text(
                'allocation_disclaimer'.tr(),
                style: tt.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        if (state.dirty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              AppDimens.sp8,
              AppDimens.pageHorizontal,
              AppDimens.sp16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!draft.sumsTo100)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppDimens.sp8),
                    child: Text(
                      'allocation_save_needs_100'.tr(
                        namedArgs: {'sum': pct.format(sum)},
                      ),
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                PositionPrimaryButton(
                  label: 'allocation_save'.tr(),
                  loading: state.saving,
                  onPressed: state.canSave ? onSave : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SumLine extends StatelessWidget {
  const _SumLine({
    required this.sum,
    required this.ok,
    required this.onNormalize,
  });

  final double sum;
  final bool ok;
  final VoidCallback onNormalize;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final f = NumberFormat.decimalPatternDigits(decimalDigits: 1);
    final diff = (100 - sum).abs();
    final line = Row(
      children: [
        Icon(
          ok ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
          size: AppDimens.iconMd,
          color: ok ? colors.profit : colors.accentWarm,
        ),
        const SizedBox(width: AppDimens.sp8),
        Expanded(
          child: Text(
            ok
                ? 'allocation_sum_ok'.tr()
                : (sum < 100 ? 'allocation_sum_missing' : 'allocation_sum_over')
                    .tr(
                      namedArgs: {'sum': f.format(sum), 'diff': f.format(diff)},
                    ),
            style: tt.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
    if (ok) return line;
    // El botón abajo: al lado del texto no entra en pantallas angostas.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line,
        TextButton(
          onPressed: onNormalize,
          child: Text('allocation_normalize'.tr()),
        ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.threshold,
    required this.onTap,
  });

  final AllocationRow row;
  final double threshold;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final f = NumberFormat.decimalPatternDigits(decimalDigits: 1);
    final off =
        row.targetPct > 0 || row.currentPct > 0
            ? row.drift.abs() >= threshold
            : false;
    final driftText =
        '${row.drift >= 0 ? '+' : '-'}${f.format(row.drift.abs())}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp8),
      child: Material(
        color: colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.sp12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.ticker,
                        style: tt.titleSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDimens.sp8),
                    Flexible(
                      child: Text(
                        'allocation_drift_points'.tr(
                          namedArgs: {'points': driftText},
                        ),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: off ? colors.accentWarm : colors.textSecondary,
                          fontWeight: off ? FontWeight.w700 : FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.sp8),
                _Bars(current: row.currentPct, target: row.targetPct),
                const SizedBox(height: AppDimens.sp6),
                Text(
                  'allocation_row_detail'.tr(
                    namedArgs: {
                      'current': f.format(row.currentPct),
                      'target': f.format(row.targetPct),
                    },
                  ),
                  style: tt.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Peso de hoy (barra) contra el objetivo (marca vertical).
class _Bars extends StatelessWidget {
  const _Bars({required this.current, required this.target});

  final double current;
  final double target;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return ExcludeSemantics(
      child: SizedBox(
        height: 10,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: colors.track,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                Container(
                  width: w * (current / 100).clamp(0, 1),
                  decoration: BoxDecoration(
                    color: colors.textPrimary.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                if (target > 0)
                  Positioned(
                    left: (w * (target / 100).clamp(0, 1) - 1).clamp(0, w - 2),
                    top: -3,
                    bottom: -3,
                    child: Container(width: 2, color: colors.accentWarm),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ContributionCard extends StatefulWidget {
  const _ContributionCard({
    required this.amount,
    required this.values,
    required this.targets,
  });

  final TextEditingController amount;
  final Map<String, double> values;

  /// Vacío si el plan no suma 100 (no hay reparto que calcular).
  final Map<String, double> targets;

  @override
  State<_ContributionCard> createState() => _ContributionCardState();
}

class _ContributionCardState extends State<_ContributionCard> {
  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final amount = parseUserNumber(widget.amount.text) ?? 0;
    final split = AllocationMath.contribution(
      values: widget.values,
      targets: widget.targets,
      amount: amount,
    );
    final entries =
        split.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
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
            'allocation_contribution_title'.tr(),
            style: tt.titleSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppDimens.sp4),
          Text(
            'allocation_contribution_body'.tr(),
            style: tt.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.sp12),
          TextField(
            controller: widget.amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'allocation_contribution_amount'.tr(),
              prefixText: '\$ ',
            ),
          ),
          if (widget.targets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.sp12),
              child: Text(
                'allocation_contribution_needs_plan'.tr(),
                style: tt.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            )
          else if (entries.isNotEmpty) ...[
            const SizedBox(height: AppDimens.sp12),
            Text(
              'allocation_contribution_result'.tr(),
              style: tt.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppDimens.sp8),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      AppNumberFormat.money(e.value),
                      style: tt.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
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

class _AlertSettings extends StatelessWidget {
  const _AlertSettings({
    required this.threshold,
    required this.notify,
    required this.onThreshold,
    required this.onNotify,
  });

  final double threshold;
  final bool notify;
  final ValueChanged<double> onThreshold;
  final ValueChanged<bool> onNotify;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    // Material (no un Container decorado): el SwitchListTile pinta su
    // fondo y el splash en el Material más cercano.
    return Material(
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
            const SizedBox(height: AppDimens.sp8),
            Text(
              'allocation_threshold'.tr(),
              style: tt.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppDimens.sp8),
            SegmentedChoice<double>(
              options: [
                for (final p in const [3.0, 5.0, 10.0])
                  (
                    value: p,
                    label: 'allocation_threshold_option'.tr(
                      namedArgs: {'points': p.toStringAsFixed(0)},
                    ),
                  ),
              ],
              selected: threshold,
              onChanged: onThreshold,
            ),
          ],
        ),
      ),
    );
  }
}

/// Resultado de la hoja de objetivo. [percent] 0 = sacarlo del plan.
class TargetEdit {
  const TargetEdit(this.ticker, this.percent);

  final String ticker;
  final double percent;
}

/// Cambiar el objetivo de un ticker (o sumar uno nuevo si [ticker] es null).
class TargetSheet extends StatefulWidget {
  const TargetSheet({super.key, this.ticker, this.current});

  final String? ticker;
  final double? current;

  static Future<TargetEdit?> show(
    BuildContext context, {
    String? ticker,
    double? current,
  }) => showModalBottomSheet<TargetEdit>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => TargetSheet(ticker: ticker, current: current),
  );

  @override
  State<TargetSheet> createState() => _TargetSheetState();
}

class _TargetSheetState extends State<TargetSheet> {
  late final _ticker = TextEditingController(text: widget.ticker ?? '');
  late final _percent = TextEditingController(
    text:
        widget.current == null || widget.current == 0
            ? ''
            : NumberFormat('0.##').format(widget.current),
  );
  String? _error;

  @override
  void dispose() {
    _ticker.dispose();
    _percent.dispose();
    super.dispose();
  }

  void _save() {
    final ticker = _ticker.text.trim().toUpperCase();
    final pct = parseUserNumber(_percent.text);
    if (!RegExp(r'^[A-Z0-9.\-^=]{1,15}$').hasMatch(ticker)) {
      setState(() => _error = 'allocation_error_ticker'.tr());
      return;
    }
    if (pct == null || pct < 0 || pct > 100) {
      setState(() => _error = 'allocation_error_percent'.tr());
      return;
    }
    Navigator.of(context).pop(TargetEdit(ticker, pct));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final adding = widget.ticker == null;
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
                adding
                    ? 'allocation_add'.tr()
                    : 'allocation_edit_title'.tr(
                      namedArgs: {'ticker': widget.ticker!},
                    ),
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimens.sp16),
              if (adding) ...[
                TextField(
                  controller: _ticker,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'import_edit_ticker'.tr(),
                    helperText: 'import_edit_ticker_help'.tr(),
                  ),
                ),
                const SizedBox(height: AppDimens.sp12),
              ],
              TextField(
                controller: _percent,
                autofocus: !adding,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'allocation_target_label'.tr(),
                  suffixText: '%',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppDimens.sp8),
                Text(
                  _error!,
                  style: tt.bodySmall?.copyWith(color: colors.loss),
                ),
              ],
              const SizedBox(height: AppDimens.sp20),
              PositionPrimaryButton(
                label: 'allocation_target_save'.tr(),
                onPressed: _save,
              ),
              if (!adding && (widget.current ?? 0) > 0)
                Center(
                  child: TextButton(
                    onPressed:
                        () => Navigator.of(
                          context,
                        ).pop(TargetEdit(widget.ticker!, 0)),
                    child: Text('allocation_target_remove'.tr()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

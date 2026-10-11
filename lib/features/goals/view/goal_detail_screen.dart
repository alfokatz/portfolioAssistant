import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/goals/view/goal_analysis.dart';
import 'package:portfolio_assistant/features/goals/view/goals_screen.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

/// Una meta: cuánto lleva y si va en camino (el análisis de Porty), el plan
/// que armó Porty (ahorro mensual, cartera y compra mensual) y qué cuenta
/// para la meta: sus inversiones asignadas (se suman solas, con el valor de
/// hoy) y lo que tiene fuera de la app. El usuario nunca carga aportes.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  Future<void> _editOutside(
    BuildContext context,
    WidgetRef ref,
    double current,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OutsideSavingsSheet(goalId: goalId, current: current),
    );
    if (saved == true) {
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'goal_outside_saved'.tr());
    }
  }

  Future<void> _editLinks(BuildContext context, UserGoal goal) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _LinkHoldingsSheet(goal: goal),
      );

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('goal_delete_title'.tr()),
            content: Text('goal_delete_body'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('porty_memory_cancel'.tr()),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('goal_delete_confirm'.tr()),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(goalsProvider.notifier).delete(goalId);
      if (context.mounted) Navigator.of(context).maybePop();
    } catch (_) {
      ref.read(alertProvider.notifier).showError(message: 'goal_error'.tr());
    }
  }

  Future<void> _setStatus(WidgetRef ref, GoalStatus status) async {
    try {
      await ref.read(goalsProvider.notifier).setStatus(goalId, status);
    } catch (_) {
      ref.read(alertProvider.notifier).showError(message: 'goal_error'.tr());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final goal = ref.watch(goalsProvider).byId(goalId);
    if (goal == null) {
      return Scaffold(appBar: AppBar());
    }
    final locale = Localizations.localeOf(context);
    final holdings = ref.watch(goalHoldingsProvider);
    final progress = GoalProgress.of(goal, DateTime.now(), holdings: holdings);
    final statusColor = GoalAnalysis.statusColor(progress.status, colors);
    final plan = goal.snapshot.plan;
    final date = DateFormat.yMMMM(locale.toLanguageTag()).format(goal.targetDate);
    final active = goal.status == GoalStatus.active;

    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, color: colors.textPrimary),
            onSelected: (value) {
              switch (value) {
                case 'achieved':
                  _setStatus(ref, GoalStatus.achieved);
                case 'active':
                  _setStatus(ref, GoalStatus.active);
                case 'delete':
                  _delete(context, ref);
              }
            },
            itemBuilder:
                (_) => [
                  if (active)
                    PopupMenuItem(
                      value: 'achieved',
                      child: Text('goal_mark_achieved'.tr()),
                    )
                  else
                    PopupMenuItem(
                      value: 'active',
                      child: Text('goal_mark_active'.tr()),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('goal_delete'.tr()),
                  ),
                ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp32,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              goal.label,
              style: tt.displaySmall?.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp4),
          Text(
            'goals_card_subtitle'.tr(
              namedArgs: {'amount': QaFormat.money(goal.targetAmount), 'date': date},
            ),
            style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.sp20),
          // Cuánto lleva.
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      QaFormat.money(progress.saved),
                      style: tt.displaySmall?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppDimens.sp6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'goal_of_target'.tr(
                          namedArgs: {'target': QaFormat.money(goal.targetAmount)},
                        ),
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.sp12),
                GoalProgressBar(
                  fraction: progress.fraction,
                  color: statusColor,
                  height: 10,
                ),
                const SizedBox(height: AppDimens.sp16),
                // El análisis de Porty.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ExcludeSemantics(child: PortyAvatar(size: 36)),
                    const SizedBox(width: AppDimens.sp12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            GoalAnalysis.statusLabel(progress.status),
                            style: tt.labelLarge?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            GoalAnalysis.text(goal, progress, locale),
                            style: tt.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          // Qué cuenta para la meta: se suma solo.
          _SectionTitle('goal_counts_title'.tr()),
          _Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final t in goal.linkedTickers.toList()..sort()) ...[
                  ListTile(
                    leading: const Icon(Icons.show_chart_rounded),
                    title: Text(
                      t,
                      style: tt.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    subtitle:
                        (holdings[t] ?? 0) > 0
                            ? null
                            : Text(
                              'goal_counts_not_held'.tr(),
                              style: tt.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                    trailing: Text(
                      QaFormat.money(holdings[t] ?? 0),
                      style: tt.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: AppDimens.cardPadding,
                    endIndent: AppDimens.cardPadding,
                    color: colors.border,
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(
                    'goal_outside_title'.tr(),
                    style: tt.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'goal_outside_subtitle'.tr(),
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                  trailing: Text(
                    QaFormat.money(goal.externalSavings),
                    style: tt.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  onTap:
                      () => _editOutside(context, ref, goal.externalSavings),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.sp8),
          Text(
            goal.linkedTickers.isEmpty
                ? 'goal_counts_hint_empty'.tr()
                : 'goal_counts_hint'.tr(),
            style: tt.bodySmall?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppDimens.sp8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _editLinks(context, goal),
              icon: Icon(Icons.tune_rounded, color: colors.accentBlue),
              label: Text(
                'goal_counts_edit'.tr(),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          // El plan de Porty.
          _SectionTitle('goal_plan_title'.tr()),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Row(
                  label: 'goal_plan_monthly'.tr(),
                  value: QaFormat.money(plan.monthlyUsed),
                ),
                _Row(
                  label: 'goal_plan_months_left'.tr(),
                  value: 'goal_months'.plural(progress.monthsRemaining),
                ),
                const SizedBox(height: AppDimens.sp12),
                Text(
                  'goal_plan_allocation'.tr(),
                  style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppDimens.sp6),
                for (final e in plan.allocation.entries)
                  _Row(
                    label: e.key.label,
                    value: '${(e.value * 100).round()}%',
                  ),
                if (goal.snapshot.buyPlan.isNotEmpty) ...[
                  const SizedBox(height: AppDimens.sp12),
                  Text(
                    'goal_plan_buy'.tr(),
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppDimens.sp6),
                  for (final e in goal.snapshot.buyPlan)
                    _Row(
                      label:
                          e.name == null ? e.ticker : '${e.ticker} · ${e.name}',
                      value: 'goal_plan_buy_amount'.tr(
                        namedArgs: {'amount': QaFormat.money(e.monthlyAmount)},
                      ),
                    ),
                ],
                const SizedBox(height: AppDimens.sp8),
                Text(
                  'goal_plan_note'.tr(
                    namedArgs: {
                      'return': QaFormat.pct(
                        plan.returns[PlanScenario.base]! * 100,
                      ),
                    },
                  ),
                  style: tt.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          OutlinedButton.icon(
            onPressed:
                () => GotoAssistant(
                  initialQuestion: 'goal_ask_porty_question'.tr(
                    namedArgs: {'goal': goal.label},
                  ),
                ).navigate(context: context),
            icon: Icon(Icons.chat_bubble_outline_rounded, color: colors.accentBlue),
            label: Text(
              'goal_ask_porty'.tr(),
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppDimens.touchTarget + 4),
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusPill),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp24),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(AppDimens.cardPadding),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    // Material (no Container con color): las filas tocables (ListTile)
    // pintan su ripple en el Material más cercano.
    return Material(
      color: colors.surfaceCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: AppDimens.sp4, bottom: AppDimens.sp8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.customColors.textSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: AppDimens.sp8),
          Text(
            value,
            style: tt.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Ahorros fuera de la app": un solo monto total (banco, efectivo…).
class _OutsideSavingsSheet extends ConsumerStatefulWidget {
  const _OutsideSavingsSheet({required this.goalId, required this.current});

  final String goalId;
  final double current;

  @override
  ConsumerState<_OutsideSavingsSheet> createState() =>
      _OutsideSavingsSheetState();
}

class _OutsideSavingsSheetState extends ConsumerState<_OutsideSavingsSheet> {
  late final _amount = TextEditingController(
    text: widget.current > 0 ? widget.current.round().toString() : '',
  );
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? get _value {
    final text = _amount.text.trim();
    if (text.isEmpty) return 0;
    final v = double.tryParse(text.replaceAll(',', '.'));
    return v == null || v < 0 ? null : v;
  }

  Future<void> _save() async {
    final value = _value;
    if (value == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(goalsProvider.notifier)
          .setExternalSavings(widget.goalId, value);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      ref.read(alertProvider.notifier).showError(message: 'goal_error'.tr());
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        MediaQuery.viewInsetsOf(context).bottom + AppDimens.sp24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'goal_outside_title'.tr(),
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.sp8),
          Text(
            'goal_outside_body'.tr(),
            style: tt.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(prefixText: r'$ ', hintText: '0'),
          ),
          const SizedBox(height: AppDimens.sp16),
          PositionPrimaryButton(
            label: 'porty_memory_save'.tr(),
            loading: _saving,
            onPressed: _saving || _value == null ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// "Elegir qué cuenta": las inversiones de la cartera (y las del plan que
/// todavía no tiene). Cada una cuenta para una sola meta: elegir una que
/// está en otra la mueve a esta.
class _LinkHoldingsSheet extends ConsumerStatefulWidget {
  const _LinkHoldingsSheet({required this.goal});

  final UserGoal goal;

  @override
  ConsumerState<_LinkHoldingsSheet> createState() => _LinkHoldingsSheetState();
}

class _LinkHoldingsSheetState extends ConsumerState<_LinkHoldingsSheet> {
  late final Set<String> _selected = {...widget.goal.linkedTickers};
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(goalsProvider.notifier)
          .setLinkedTickers(widget.goal.id, _selected);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      ref.read(alertProvider.notifier).showError(message: 'goal_error'.tr());
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final holdings = ref.watch(goalHoldingsProvider);
    final goals = ref.watch(goalsProvider).goals;
    final tickers =
        {
            ...holdings.keys,
            for (final e in widget.goal.snapshot.buyPlan) e.ticker.toUpperCase(),
            ...widget.goal.linkedTickers,
          }.toList()
          ..sort();
    String? ownerOf(String t) =>
        goals
            .where((g) => g.id != widget.goal.id && g.linkedTickers.contains(t))
            .firstOrNull
            ?.label;

    return SafeArea(
      child: Padding(
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
              'goal_counts_edit'.tr(),
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              'goal_link_body'.tr(),
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in tickers)
                    CheckboxListTile(
                      value: _selected.contains(t),
                      onChanged:
                          (on) => setState(
                            () => on == true ? _selected.add(t) : _selected.remove(t),
                          ),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t,
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        [
                          (holdings[t] ?? 0) > 0
                              ? QaFormat.money(holdings[t]!)
                              : 'goal_counts_not_held'.tr(),
                          if (ownerOf(t) case final owner?)
                            'goal_link_in_other'.tr(namedArgs: {'goal': owner}),
                        ].join(' · '),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.sp12),
            PositionPrimaryButton(
              label: 'porty_memory_save'.tr(),
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

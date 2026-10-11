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
/// que armó Porty (ahorro mensual, cartera y compra mensual) y sus aportes.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  Future<void> _addContribution(BuildContext context, WidgetRef ref) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ContributionSheet(goalId: goalId),
    );
    if (added == true) {
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'goal_contribution_added'.tr());
    }
  }

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
    final progress = GoalProgress.of(goal, DateTime.now());
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
                if (active) ...[
                  const SizedBox(height: AppDimens.sp16),
                  PositionPrimaryButton(
                    label: 'goal_add_contribution'.tr(),
                    onPressed: () => _addContribution(context, ref),
                  ),
                ],
              ],
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
          _SectionTitle('goal_contributions_title'.tr()),
          if (goal.contributions.isEmpty)
            Text(
              'goal_contributions_empty'.tr(),
              style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
            )
          else
            _Card(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, c) in goal.contributions.reversed.indexed) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: AppDimens.cardPadding,
                        endIndent: AppDimens.cardPadding,
                        color: colors.border,
                      ),
                    ListTile(
                      title: Text(
                        QaFormat.signedMoney(c.amount),
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        [
                          DateFormat.yMMMd(locale.toLanguageTag()).format(c.date),
                          if (c.note != null && c.note!.isNotEmpty) c.note!,
                        ].join(' · '),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: 'porty_memory_delete'.tr(),
                        icon: Icon(
                          Icons.close_rounded,
                          size: AppDimens.iconMd,
                          color: colors.textSecondary,
                        ),
                        onPressed:
                            () => ref
                                .read(goalsProvider.notifier)
                                .removeContribution(c.id),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
    return Container(
      width: double.infinity,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: child,
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

/// "Registrar aporte": cuánto puso (o sacó, con "retiro") y cuándo.
class _ContributionSheet extends ConsumerStatefulWidget {
  const _ContributionSheet({required this.goalId});

  final String goalId;

  @override
  ConsumerState<_ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends ConsumerState<_ContributionSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _withdrawal = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _value {
    final v = double.tryParse(_amount.text.replaceAll(',', '.'));
    return v == null || v <= 0 ? null : v;
  }

  Future<void> _save() async {
    final value = _value;
    if (value == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(goalsProvider.notifier)
          .addContribution(
            widget.goalId,
            amount: _withdrawal ? -value : value,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
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
            'goal_add_contribution'.tr(),
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text('goal_contribution_deposit'.tr()),
              ),
              ButtonSegment(
                value: true,
                label: Text('goal_contribution_withdrawal'.tr()),
              ),
            ],
            selected: {_withdrawal},
            showSelectedIcon: false,
            onSelectionChanged:
                (value) => setState(() => _withdrawal = value.first),
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
            decoration: InputDecoration(
              prefixText: r'$ ',
              hintText: 'goal_contribution_amount_hint'.tr(),
            ),
          ),
          const SizedBox(height: AppDimens.sp12),
          TextField(
            controller: _note,
            maxLength: 140,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: 'goal_contribution_note_hint'.tr(),
            ),
          ),
          const SizedBox(height: AppDimens.sp12),
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

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/allocation/providers/allocation_provider.dart';
import 'package:portfolio_assistant/features/allocation/view/widgets/allocation_widgets.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/confirm_sheet.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';
import 'package:portfolio_assistant/shared/utils/user_number.dart';

enum AllocationStep { pick, split, alerts, review }

/// Armar (o cambiar) el plan de cartera de a un paso, con Porty guiando:
/// 1. qué quiere tener; 2. cuánto de cada una (siempre suma 100: al mover
/// una, Porty ajusta las demás); 3. cuándo le avisa; 4. repaso y guardar.
/// Devuelve `true` si guardó.
class AllocationWizardScreen extends ConsumerStatefulWidget {
  const AllocationWizardScreen({
    super.key,
    this.initial,
    this.startAt = AllocationStep.pick,
  });

  /// El plan guardado, si está cambiando uno.
  final AllocationPlan? initial;
  final AllocationStep startAt;

  static Future<bool> open(
    BuildContext context, {
    AllocationPlan? initial,
    AllocationStep startAt = AllocationStep.pick,
  }) async =>
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder:
              (_) => AllocationWizardScreen(initial: initial, startAt: startAt),
        ),
      ) ??
      false;

  @override
  ConsumerState<AllocationWizardScreen> createState() =>
      _AllocationWizardScreenState();
}

class _AllocationWizardScreenState
    extends ConsumerState<AllocationWizardScreen> {
  late final PageController _pages;
  late AllocationStep _step;

  /// Todos los tickers que se muestran en el paso 1 (lo que tiene y lo que
  /// sumó), en orden.
  late List<String> _candidates;

  /// Los marcados, en el orden de [_candidates].
  late Set<String> _picked;

  /// El reparto (enteros que suman 100) de lo marcado.
  Map<String, int> _split = const {};
  final Set<String> _locked = {};

  late double _threshold;
  late bool _notify;
  late AllocationAlertFrequency _frequency;

  Map<String, double> get _values => ref.read(goalHoldingsProvider);

  List<String> get _selection => [
    for (final t in _candidates)
      if (_picked.contains(t)) t,
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final values = _values;
    final held =
        values.keys.where((t) => (values[t] ?? 0) > 0).toList()
          ..sort((a, b) => values[b]!.compareTo(values[a]!));
    if (initial != null && !initial.isEmpty) {
      final planned =
          initial.targets.keys.toList()..sort(
            (a, b) => initial.targets[b]!.compareTo(initial.targets[a]!),
          );
      _candidates = [
        ...planned,
        for (final t in held)
          if (!planned.contains(t)) t,
      ];
      _picked = planned.toSet();
      _split = {
        for (final e in AllocationMath.roundTo100(initial.targets).entries)
          e.key: e.value.round(),
      };
    } else {
      _candidates = held;
      _picked = held.toSet();
    }
    _threshold =
        (initial?.driftThreshold ?? 5)
            .clamp(allocationMinThreshold, allocationMaxThreshold)
            .toDouble();
    _notify = initial?.notify ?? true;
    _frequency = initial?.frequency ?? AllocationAlertFrequency.weekly;
    _step = _picked.isEmpty ? AllocationStep.pick : widget.startAt;
    if (_step != AllocationStep.pick) _syncSplit();
    _pages = PageController(initialPage: _step.index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Duration get _slide =>
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300);

  AllocationPlan get _plan => AllocationPlan(
    targets: {
      for (final t in _selection)
        if ((_split[t] ?? 0) > 0) t: _split[t]!.toDouble(),
    },
    driftThreshold: _threshold,
    notify: _notify,
    frequency: _frequency,
  );

  bool get _dirty => widget.initial == null || _plan != widget.initial;

  /// Ajusta el reparto a lo marcado: lo que sigue conserva su peso (y se
  /// reescala a 100), lo nuevo entra en 0. Sin nada previo, los pesos de
  /// hoy.
  void _syncSplit() {
    final selection = _selection;
    if (selection.isEmpty) {
      _split = const {};
      return;
    }
    if (_split.keys.toSet().containsAll(selection) &&
        selection.toSet().containsAll(_split.keys)) {
      return;
    }
    final kept = {
      for (final t in selection)
        if ((_split[t] ?? 0) > 0) t: _split[t]!.toDouble(),
    };
    if (kept.isEmpty) {
      _split = AllocationMath.initialSplit(tickers: selection, values: _values);
    } else {
      final scaled = AllocationMath.roundTo100(kept);
      _split = {for (final t in selection) t: (scaled[t] ?? 0).round()};
    }
    _locked.removeWhere((t) => !selection.contains(t));
  }

  void _goTo(AllocationStep step) {
    FocusScope.of(context).unfocus();
    if (step.index > AllocationStep.pick.index) _syncSplit();
    setState(() => _step = step);
    _pages.animateToPage(
      step.index,
      duration: _slide,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _back() async {
    if (_step != AllocationStep.pick) {
      _goTo(AllocationStep.values[_step.index - 1]);
      return;
    }
    if (_dirty && _picked.isNotEmpty) {
      final leave = await ConfirmSheet.show(
        context,
        title: 'allocation_wizard_leave_title'.tr(),
        body: 'allocation_wizard_leave_body'.tr(),
        confirmLabel: 'allocation_wizard_leave'.tr(),
      );
      if (!leave || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _addTicker() async {
    final ticker = await _AddTickerSheet.show(context, existing: _candidates);
    if (ticker == null || !mounted) return;
    setState(() {
      _candidates = [..._candidates, ticker];
      _picked = {..._picked, ticker};
    });
  }

  Future<void> _save() async {
    final notifier = ref.read(allocationProvider.notifier);
    final ok = await notifier.save(_plan);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    final error = ref.read(allocationProvider).error;
    if (error == AllocationError.locked) {
      SubscriptionPaywallSheet.show(
        context,
        ref,
        reason: PaywallReason.modeLocked,
      );
    } else {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'allocation_error_save'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final values = ref.watch(goalHoldingsProvider);
    final saving = ref.watch(allocationProvider.select((s) => s.saving));
    final total = values.values.where((v) => v > 0).fold(0.0, (a, b) => a + b);
    final currentPct = {
      for (final e in values.entries)
        if (e.value > 0 && total > 0) e.key: e.value / total * 100,
    };
    final steps = AllocationStep.values.length;

    final (label, onNext) = switch (_step) {
      AllocationStep.pick => (
        'allocation_wizard_next'.tr(),
        _picked.isEmpty ? null : () => _goTo(AllocationStep.split),
      ),
      AllocationStep.split => (
        'allocation_wizard_next'.tr(),
        () => _goTo(AllocationStep.alerts),
      ),
      AllocationStep.alerts => (
        'allocation_wizard_review'.tr(),
        () => _goTo(AllocationStep.review),
      ),
      AllocationStep.review => ('allocation_save'.tr(), saving ? null : _save),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const BackButtonIcon(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _back,
          ),
          title: Text(
            'allocation_wizard_step'.tr(
              namedArgs: {'current': '${_step.index + 1}', 'total': '$steps'},
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pageHorizontal,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: (_step.index + 1) / steps),
                  duration: _slide,
                  builder:
                      (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 3,
                        color: colors.accentBlue,
                        backgroundColor: colors.surfaceElevated,
                      ),
                ),
              ),
            ),
          ),
        ),
        body: PageView(
          controller: _pages,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _PickStep(
              candidates: _candidates,
              picked: _picked,
              currentPct: currentPct,
              onToggle:
                  (t) => setState(() {
                    _picked =
                        _picked.contains(t)
                            ? ({..._picked}..remove(t))
                            : {..._picked, t};
                  }),
              onAdd: _addTicker,
            ),
            _SplitStep(
              selection: _selection,
              split: _split,
              locked: _locked,
              currentPct: currentPct,
              onChanged: (split) => setState(() => _split = split),
              onToggleLock:
                  (t) => setState(() {
                    if (!_locked.remove(t)) _locked.add(t);
                  }),
              onPreset: (split) {
                setState(() {
                  _split = split;
                  _locked.clear();
                });
              },
            ),
            _ScrollStep(
              children: [
                PortySays(
                  messageKey: 'alerts',
                  message: Text('allocation_alerts_porty'.tr()),
                  footnote: Text('allocation_alerts_porty_note'.tr()),
                ),
                const SizedBox(height: AppDimens.sp20),
                AlertSettingsEditor(
                  threshold: _threshold,
                  notify: _notify,
                  frequency: _frequency,
                  targets: _plan.targets,
                  currentPct: currentPct,
                  onThreshold: (v) => setState(() => _threshold = v),
                  onNotify: (v) => setState(() => _notify = v),
                  onFrequency: (v) => setState(() => _frequency = v),
                ),
              ],
            ),
            _ReviewStep(
              plan: _plan,
              order: _selection,
              currentPct: currentPct,
              onEdit: _goTo,
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              AppDimens.sp8,
              AppDimens.pageHorizontal,
              AppDimens.sp16,
            ),
            child: PositionPrimaryButton(
              label: label,
              loading: _step == AllocationStep.review && saving,
              onPressed: onNext,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cada paso scrollea por su cuenta (el botón queda fijo abajo).
class _ScrollStep extends StatelessWidget {
  const _ScrollStep({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppDimens.pageHorizontal,
      AppDimens.sp20,
      AppDimens.pageHorizontal,
      AppDimens.sp24,
    ),
    children: children,
  );
}

// ---------------------------------------------------------------------------
// Paso 1: qué quiere tener
// ---------------------------------------------------------------------------

class _PickStep extends StatelessWidget {
  const _PickStep({
    required this.candidates,
    required this.picked,
    required this.currentPct,
    required this.onToggle,
    required this.onAdd,
  });

  final List<String> candidates;
  final Set<String> picked;
  final Map<String, double> currentPct;
  final ValueChanged<String> onToggle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final hasHoldings = currentPct.isNotEmpty;
    final leftOut = [
      for (final t in candidates)
        if (!picked.contains(t) && (currentPct[t] ?? 0) > 0) t,
    ];
    return _ScrollStep(
      children: [
        PortySays(
          messageKey: 'pick',
          message: Text(
            (hasHoldings
                    ? 'allocation_pick_porty'
                    : 'allocation_pick_porty_empty')
                .tr(),
          ),
        ),
        const SizedBox(height: AppDimens.sp20),
        if (candidates.isNotEmpty)
          AllocationCard(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.sp4),
            child: Column(
              children: [
                for (final (i, t) in candidates.indexed) ...[
                  if (i > 0) Divider(height: 1, color: colors.border),
                  CheckboxListTile.adaptive(
                    value: picked.contains(t),
                    onChanged: (_) => onToggle(t),
                    controlAffinity: ListTileControlAffinity.trailing,
                    activeColor: colors.accentBlue,
                    title: Text(
                      t,
                      style: tt.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      (currentPct[t] ?? 0) > 0
                          ? 'allocation_pick_today'.tr(
                            namedArgs: {'pct': allocationPct(currentPct[t]!)},
                          )
                          : 'allocation_pick_new'.tr(),
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppDimens.sp8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: Text('allocation_add'.tr()),
          ),
        ),
        if (leftOut.isNotEmpty) ...[
          const SizedBox(height: AppDimens.sp8),
          _Note(
            icon: Icons.info_outline_rounded,
            text: 'allocation_pick_left_out'.tr(
              namedArgs: {'tickers': leftOut.join(', ')},
            ),
          ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppDimens.sp12),
      decoration: BoxDecoration(
        color: colors.inset,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppDimens.iconSm, color: colors.textSecondary),
          const SizedBox(width: AppDimens.sp8),
          Expanded(
            child: Text(
              text,
              style: tt.bodySmall?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 2: cuánto de cada una (siempre suma 100)
// ---------------------------------------------------------------------------

class _SplitStep extends StatelessWidget {
  const _SplitStep({
    required this.selection,
    required this.split,
    required this.locked,
    required this.currentPct,
    required this.onChanged,
    required this.onToggleLock,
    required this.onPreset,
  });

  final List<String> selection;
  final Map<String, int> split;
  final Set<String> locked;
  final Map<String, double> currentPct;
  final ValueChanged<Map<String, int>> onChanged;
  final ValueChanged<String> onToggleLock;
  final ValueChanged<Map<String, int>> onPreset;

  /// Un dato del reparto, no un consejo: cuánto depende de una sola.
  String? _insight() {
    final shown = [
      for (final t in selection)
        if ((split[t] ?? 0) > 0) t,
    ];
    if (shown.isEmpty) return null;
    if (shown.length == 1) {
      return 'allocation_split_insight_single'.tr(
        namedArgs: {'ticker': shown.first},
      );
    }
    final top = shown.reduce((a, b) => split[a]! >= split[b]! ? a : b);
    final topPct = split[top]!;
    if (topPct >= 50) {
      return 'allocation_split_insight_concentrated'.tr(
        namedArgs: {'ticker': top, 'pct': '$topPct'},
      );
    }
    if (topPct <= 35) return 'allocation_split_insight_spread'.tr();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final heldSelected = {
      for (final t in selection)
        if ((currentPct[t] ?? 0) > 0) t: currentPct[t]!,
    };
    final today =
        heldSelected.isEmpty
            ? null
            : AllocationMath.initialSplit(
              tickers: selection,
              values: heldSelected,
            );
    final equal = AllocationMath.equalSplit(selection);
    bool same(Map<String, int>? a) =>
        a != null && selection.every((t) => a[t] == split[t]);
    final insight = _insight();
    final single = selection.length == 1;

    return _ScrollStep(
      children: [
        PortySays(
          messageKey: 'split',
          message: Text(
            (single
                    ? 'allocation_split_porty_single'
                    : 'allocation_split_porty')
                .tr(),
          ),
          footnote: insight == null ? null : Text(insight),
        ),
        const SizedBox(height: AppDimens.sp20),
        AllocationCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'allocation_split_bar_title'.tr(),
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.check_circle_rounded,
                    size: AppDimens.iconSm,
                    color: colors.profit,
                  ),
                  const SizedBox(width: AppDimens.sp4),
                  Flexible(
                    child: Text(
                      'allocation_split_total'.tr(),
                      style: tt.bodySmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.sp8),
              PlanBar(
                slices: [
                  for (final (i, t) in selection.indexed)
                    (
                      ticker: t,
                      pct: (split[t] ?? 0).toDouble(),
                      color: allocationColor(context, i),
                    ),
                ],
              ),
              if (!single) ...[
                const SizedBox(height: AppDimens.sp12),
                Wrap(
                  spacing: AppDimens.sp8,
                  runSpacing: AppDimens.sp8,
                  children: [
                    if (today != null)
                      ChoiceChip(
                        label: Text('allocation_preset_today'.tr()),
                        selected: same(today),
                        onSelected: (_) => onPreset(today),
                      ),
                    ChoiceChip(
                      label: Text('allocation_preset_equal'.tr()),
                      selected: same(equal),
                      onSelected: (_) => onPreset(equal),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppDimens.sp12),
        for (final (i, t) in selection.indexed)
          _SplitRow(
            ticker: t,
            color: allocationColor(context, i),
            pct: split[t] ?? 0,
            today: currentPct[t],
            locked: locked.contains(t),
            enabled: !single,
            onChanged:
                (v) => onChanged(
                  AllocationMath.rebalance(
                    targets: split,
                    ticker: t,
                    value: v,
                    locked: locked,
                  ),
                ),
            onToggleLock: () => onToggleLock(t),
          ),
        if (!single && selection.length > 2)
          Padding(
            padding: const EdgeInsets.only(top: AppDimens.sp4),
            child: _Note(
              icon: Icons.lock_outline_rounded,
              text: 'allocation_split_lock_hint'.tr(),
            ),
          ),
      ],
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.ticker,
    required this.color,
    required this.pct,
    required this.today,
    required this.locked,
    required this.enabled,
    required this.onChanged,
    required this.onToggleLock,
  });

  final String ticker;
  final Color color;
  final int pct;
  final double? today;
  final bool locked;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final VoidCallback onToggleLock;

  Future<void> _type(BuildContext context) async {
    final v = await _PercentSheet.show(context, ticker: ticker, current: pct);
    if (v != null) onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final zero = pct == 0;
    final todayPct = today;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp8),
      child: AllocationCard(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.sp16,
          AppDimens.sp12,
          AppDimens.sp4,
          AppDimens.sp4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PlanDot(color),
                const SizedBox(width: AppDimens.sp8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticker,
                        style: tt.titleSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        zero
                            ? 'allocation_split_zero'.tr()
                            : todayPct != null && todayPct > 0
                            ? 'allocation_split_today'.tr(
                              namedArgs: {'pct': allocationPct(todayPct)},
                            )
                            : 'allocation_pick_new'.tr(),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  button: enabled,
                  label: 'allocation_split_type'.tr(
                    namedArgs: {'ticker': ticker},
                  ),
                  child: InkWell(
                    onTap: enabled ? () => _type(context) : null,
                    borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 64,
                        minHeight: AppDimens.touchTarget,
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.sp8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.inset,
                        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                      ),
                      child: Text(
                        '$pct%',
                        style: tt.titleMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                if (enabled)
                  IconButton(
                    onPressed: onToggleLock,
                    tooltip:
                        (locked
                                ? 'allocation_split_unlock'
                                : 'allocation_split_lock')
                            .tr(),
                    icon: Icon(
                      locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      size: AppDimens.iconMd,
                      color: locked ? colors.accentBlue : colors.textSecondary,
                    ),
                  )
                else
                  const SizedBox(width: AppDimens.sp12),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                inactiveTrackColor: colors.track,
                overlayColor: color.withValues(alpha: 0.12),
                trackHeight: 4,
              ),
              child: Slider(
                value: pct.toDouble(),
                max: 100,
                divisions: 100,
                semanticFormatterCallback: (v) => '$ticker ${v.round()}%',
                onChanged:
                    enabled && !locked
                        ? (v) {
                          if (v.round() != pct) {
                            HapticFeedback.selectionClick();
                            onChanged(v.round());
                          }
                        }
                        : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Escribir el porcentaje exacto de un ticker.
class _PercentSheet extends StatefulWidget {
  const _PercentSheet({required this.ticker, required this.current});

  final String ticker;
  final int current;

  static Future<int?> show(
    BuildContext context, {
    required String ticker,
    required int current,
  }) => showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PercentSheet(ticker: ticker, current: current),
  );

  @override
  State<_PercentSheet> createState() => _PercentSheetState();
}

class _PercentSheetState extends State<_PercentSheet> {
  late final _percent = TextEditingController(text: '${widget.current}');
  String? _error;

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseUserNumber(_percent.text);
    if (v == null || v < 0 || v > 100) {
      setState(() => _error = 'allocation_error_percent'.tr());
      return;
    }
    Navigator.of(context).pop(v.round());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
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
                'allocation_edit_title'.tr(
                  namedArgs: {'ticker': widget.ticker},
                ),
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimens.sp6),
              Text(
                'allocation_edit_body'.tr(),
                style: tt.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppDimens.sp16),
              TextField(
                controller: _percent,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'allocation_target_label'.tr(),
                  suffixText: '%',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: AppDimens.sp20),
              PositionPrimaryButton(
                label: 'allocation_target_save'.tr(),
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sumar un ticker que todavía no tiene.
class _AddTickerSheet extends StatefulWidget {
  const _AddTickerSheet({required this.existing});

  final List<String> existing;

  static Future<String?> show(
    BuildContext context, {
    required List<String> existing,
  }) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddTickerSheet(existing: existing),
  );

  @override
  State<_AddTickerSheet> createState() => _AddTickerSheetState();
}

class _AddTickerSheetState extends State<_AddTickerSheet> {
  final _ticker = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _save() {
    final ticker = _ticker.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9.\-^=]{1,15}$').hasMatch(ticker)) {
      setState(() => _error = 'allocation_error_ticker'.tr());
      return;
    }
    if (widget.existing.contains(ticker)) {
      setState(() => _error = 'allocation_error_duplicate'.tr());
      return;
    }
    Navigator.of(context).pop(ticker);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
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
                'allocation_add'.tr(),
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimens.sp6),
              Text(
                'allocation_add_body'.tr(),
                style: tt.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppDimens.sp16),
              TextField(
                controller: _ticker,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'import_edit_ticker'.tr(),
                  helperText: 'import_edit_ticker_help'.tr(),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: AppDimens.sp20),
              PositionPrimaryButton(
                label: 'allocation_add_confirm'.tr(),
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 4: repaso
// ---------------------------------------------------------------------------

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.plan,
    required this.order,
    required this.currentPct,
    required this.onEdit,
  });

  final AllocationPlan plan;
  final List<String> order;
  final Map<String, double> currentPct;
  final ValueChanged<AllocationStep> onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final shown = [
      for (final t in order)
        if ((plan.targets[t] ?? 0) > 0) t,
    ];
    return _ScrollStep(
      children: [
        PortySays(
          messageKey: 'review',
          mood: PortyAvatarState.answered,
          message: Text('allocation_review_porty'.tr()),
        ),
        const SizedBox(height: AppDimens.sp20),
        AllocationCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AllocationCardTitle(
                'allocation_review_plan'.tr(),
                action: 'allocation_change'.tr(),
                onAction: () => onEdit(AllocationStep.split),
              ),
              const SizedBox(height: AppDimens.sp8),
              PlanBar(
                slices: [
                  for (final t in shown)
                    (
                      ticker: t,
                      pct: plan.targets[t]!,
                      color: allocationColor(context, order.indexOf(t)),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.sp12),
              for (final t in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      PlanDot(allocationColor(context, order.indexOf(t))),
                      const SizedBox(width: AppDimens.sp8),
                      Expanded(
                        child: Text(
                          t,
                          style: tt.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        allocationPct(plan.targets[t]!),
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.sp12),
        AllocationCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AllocationCardTitle(
                'allocation_review_alerts'.tr(),
                action: 'allocation_change'.tr(),
                onAction: () => onEdit(AllocationStep.alerts),
              ),
              const SizedBox(height: AppDimens.sp4),
              Text(
                allocationAlertSummary(plan),
                style: tt.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.sp16),
        Text(
          'allocation_disclaimer'.tr(),
          style: tt.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// "Te aviso todos los lunes si algo se aleja más de 5 puntos de tu plan."
String allocationAlertSummary(AllocationPlan plan) {
  final points = {'points': '${plan.driftThreshold.round()}'};
  if (!plan.notify) {
    return 'allocation_alert_summary_off'.tr(namedArgs: points);
  }
  return (plan.frequency == AllocationAlertFrequency.monthly
          ? 'allocation_alert_summary_monthly'
          : 'allocation_alert_summary_weekly')
      .tr(namedArgs: points);
}

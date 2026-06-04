import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_colors.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';
import 'package:portfolio_assistant/features/planning/utils/planning_enum_parser.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

abstract final class PlanningCatalogWidgets {
  static Widget goalCard(CatalogItemContext ctx) {
    final data = _GoalData.fromMap(ctx.data as JsonMap);

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _goalIcon(data.goalLabel),
                  color: const Color(0xFF2979FF),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.goalLabel,
                        style: const TextStyle(
                          color: AnalysisColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        'Meta: ${_currency.format(data.targetAmount)}',
                        style: const TextStyle(
                          color: AnalysisColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (data.currentProgress / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: PortfolioColors.border,
                color: AnalysisColors.profit,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${data.currentProgress.round()}% · ${_currency.format(data.currentSaved)} ahorrado',
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${data.monthsRemaining} meses restantes',
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Objetivo: ${_formatDate(data.targetDate)}',
              style: const TextStyle(
                color: AnalysisColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget projectionChart(CatalogItemContext ctx) {
    return _ProjectionChartWidget(ctx: ctx);
  }

  static Widget milestoneTimeline(CatalogItemContext ctx) {
    final raw = (ctx.data as JsonMap)['milestones'];
    final items = (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => _MilestoneData.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    if (items.isEmpty) return const SizedBox.shrink();

    final timeline = Column(
      children: [
        for (var i = 0; i < items.length; i++)
          _MilestoneNode(
            data: items[i],
            isLast: i == items.length - 1,
          ),
      ],
    );

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hitos del camino',
              style: TextStyle(
                color: AnalysisColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            if (items.length > 5)
              SizedBox(
                height: 320,
                child: SingleChildScrollView(child: timeline),
              )
            else
              timeline,
          ],
        ),
      ),
    );
  }

  static Widget actionPriorityCard(CatalogItemContext ctx) {
    final data = _ActionData.fromMap(ctx.data as JsonMap);
    final impactStyle = _impactStyle(data.impact);
    final effortStyle = _effortStyle(data.effort);

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2979FF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${data.priority}',
                style: const TextStyle(
                  color: Color(0xFF2979FF),
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: const TextStyle(
                      color: AnalysisColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.description,
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _Badge(label: impactStyle.label, color: impactStyle.color),
                      _Badge(label: effortStyle.label, color: effortStyle.color),
                    ],
                  ),
                  if (data.actionEvent != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => ctx.dispatchEvent(
                          UserActionEvent(
                            name: data.actionEvent!,
                            sourceComponentId: ctx.id,
                            context: const {},
                          ),
                        ),
                        child: const Text('Hacer ahora →'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget gapAnalysisCard(CatalogItemContext ctx) {
    final data = _GapData.fromMap(ctx.data as JsonMap);
    final gapPositive = data.gap <= 0;

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _GapColumn(
                    title: 'Ritmo actual',
                    amount: data.currentMonthlyContribution,
                    years: data.yearsToGoalAtCurrentRate,
                  ),
                ),
                Column(
                  children: [
                    Icon(
                      Icons.arrow_forward,
                      color: gapPositive
                          ? AnalysisColors.profit
                          : AnalysisColors.loss,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      gapPositive
                          ? 'Al día ✓'
                          : '-${_currency.format(data.gap.abs())}/mes',
                      style: TextStyle(
                        color: gapPositive
                            ? AnalysisColors.profit
                            : AnalysisColors.loss,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: _GapColumn(
                    title: 'Ritmo necesario',
                    amount: data.requiredMonthlyContribution,
                    years: data.yearsToGoalIfGapClosed,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              data.message,
              style: const TextStyle(
                color: AnalysisColors.textSecondary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  static IconData _goalIcon(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('casa') || lower.contains('hogar')) {
      return Icons.home_outlined;
    }
    if (lower.contains('emergencia') || lower.contains('fondo')) {
      return Icons.shield_outlined;
    }
    return Icons.flag_outlined;
  }

  static String _formatDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return _dateFormat.format(parsed);
  }

  static Color _parseColor(String hex, {Color fallback = PortfolioColors.chartLine}) {
    var value = hex.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) value = 'FF$value';
    final intVal = int.tryParse(value, radix: 16);
    if (intVal == null) return fallback;
    return Color(intVal);
  }

  static _Style _impactStyle(String impact) {
    switch (impact) {
      case 'high':
        return const _Style('Alto impacto', AnalysisColors.profit);
      case 'low':
        return const _Style('Bajo impacto', AnalysisColors.textSecondary);
      default:
        return const _Style('Impacto medio', Color(0xFF2979FF));
    }
  }

  static _Style _effortStyle(String effort) {
    switch (effort) {
      case 'easy':
        return const _Style('Fácil', AnalysisColors.profit);
      case 'hard':
        return const _Style('Requiere esfuerzo', AnalysisColors.loss);
      default:
        return const _Style('Moderado', AnalysisColors.textSecondary);
    }
  }
}

class _ProjectionChartWidget extends StatefulWidget {
  const _ProjectionChartWidget({required this.ctx});

  final CatalogItemContext ctx;

  @override
  State<_ProjectionChartWidget> createState() => _ProjectionChartWidgetState();
}

class _ProjectionChartWidgetState extends State<_ProjectionChartWidget> {
  late String _highlight;

  @override
  void initState() {
    super.initState();
    final data = _ProjectionData.fromMap(widget.ctx.data as JsonMap);
    _highlight = data.highlightScenario;
  }

  @override
  void didUpdateWidget(covariant _ProjectionChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final data = _ProjectionData.fromMap(widget.ctx.data as JsonMap);
    _highlight = data.highlightScenario;
  }

  @override
  Widget build(BuildContext context) {
    final data = _ProjectionData.fromMap(widget.ctx.data as JsonMap);
    final targetDate = DateTime.tryParse(data.targetDate) ?? DateTime.now();
    final now = DateTime.now();
    final months = math.max(
      1,
      ((targetDate.difference(now).inDays) / 30.44).ceil(),
    );

    final lineBars = <LineChartBarData>[];
    for (final scenario in data.scenarios) {
      final isHighlighted = scenario.label == _highlight;
      final spots = _buildSpots(
        currentValue: data.currentValue,
        projectedValue: scenario.projectedValue,
        months: months,
      );
      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: PlanningCatalogWidgets._parseColor(scenario.color),
          barWidth: isHighlighted ? 3.5 : 2,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    final maxY = [
      data.targetValue,
      data.currentValue,
      ...data.scenarios.map((s) => s.projectedValue),
    ].reduce(math.max);

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Proyección de tu meta',
              style: TextStyle(
                color: AnalysisColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: months.toDouble(),
                  minY: 0,
                  maxY: maxY * 1.1,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: PortfolioColors.chartGrid,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (value, meta) => Text(
                          _compactMoney(value),
                          style: const TextStyle(
                            color: AnalysisColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: math.max(1, months / 4).toDouble(),
                        getTitlesWidget: (value, meta) {
                          final date = DateTime(
                            now.year,
                            now.month + value.round(),
                          );
                          return Text(
                            DateFormat('MM/yy').format(date),
                            style: const TextStyle(
                              color: AnalysisColors.textSecondary,
                              fontSize: 9,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: data.targetValue,
                        color: AnalysisColors.profit.withValues(alpha: 0.6),
                        strokeWidth: 1.5,
                        dashArray: const [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          labelResolver: (_) => 'Meta',
                          style: const TextStyle(
                            color: AnalysisColors.profit,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  lineBarsData: lineBars,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: data.scenarios.map((scenario) {
                final selected = scenario.label == _highlight;
                return ChoiceChip(
                  label: Text(
                    '${scenario.label}: ${_compactMoney(scenario.monthlyRequired)}/mes',
                    style: TextStyle(
                      color: selected
                          ? AnalysisColors.textPrimary
                          : AnalysisColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  selected: selected,
                  selectedColor: PlanningCatalogWidgets._parseColor(scenario.color)
                      .withValues(alpha: 0.25),
                  backgroundColor: PortfolioColors.surfaceElevated,
                  onSelected: (_) {
                    setState(() => _highlight = scenario.label);
                    widget.ctx.dispatchEvent(
                      UserActionEvent(
                        name: 'scenario_selected',
                        sourceComponentId: widget.ctx.id,
                        context: {'label': scenario.label},
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _buildSpots({
    required double currentValue,
    required double projectedValue,
    required int months,
  }) {
    if (months <= 0) {
      return [FlSpot(0, currentValue)];
    }
    final monthlyRate =
        math.pow(projectedValue / math.max(currentValue, 1), 1 / months) - 1;
    return List.generate(months + 1, (i) {
      final value = currentValue * math.pow(1 + monthlyRate, i);
      return FlSpot(i.toDouble(), value.toDouble());
    });
  }

  String _compactMoney(double value) {
    if (value >= 1000000) return '\$${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '\$${(value / 1000).toStringAsFixed(0)}k';
    return '\$${value.round()}';
  }
}

class _MilestoneNode extends StatefulWidget {
  const _MilestoneNode({required this.data, required this.isLast});

  final _MilestoneData data;
  final bool isLast;

  @override
  State<_MilestoneNode> createState() => _MilestoneNodeState();
}

class _MilestoneNodeState extends State<_MilestoneNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.85,
      upperBound: 1.15,
    );
    if (widget.data.status == 'current') {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.data.status) {
      'completed' => AnalysisColors.profit,
      'current' => const Color(0xFF2979FF),
      _ => AnalysisColors.textSecondary,
    };

    final node = widget.data.status == 'current'
        ? ScaleTransition(
            scale: _pulseController,
            child: _circle(color, filled: true),
          )
        : _circle(color, filled: widget.data.status == 'completed');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                node,
                if (!widget.isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: PortfolioColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    PlanningCatalogWidgets._formatDate(widget.data.date),
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    widget.data.label,
                    style: const TextStyle(
                      color: AnalysisColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    PlanningCatalogWidgets._currency
                        .format(widget.data.targetValue),
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(Color color, {required bool filled}) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}

class _GapColumn extends StatelessWidget {
  const _GapColumn({
    required this.title,
    required this.amount,
    required this.years,
    this.alignEnd = false,
  });

  final String title;
  final double amount;
  final double years;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AnalysisColors.textSecondary,
            fontSize: 12,
          ),
        ),
        Text(
          PlanningCatalogWidgets._currency.format(amount),
          style: const TextStyle(
            color: AnalysisColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        Text(
          '~${years.toStringAsFixed(1)} años',
          style: const TextStyle(
            color: AnalysisColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Style {
  const _Style(this.label, this.color);
  final String label;
  final Color color;
}

class _GoalData {
  _GoalData({
    required this.goalLabel,
    required this.targetAmount,
    required this.targetDate,
    required this.currentProgress,
    required this.currentSaved,
    required this.monthsRemaining,
  });

  final String goalLabel;
  final double targetAmount;
  final String targetDate;
  final double currentProgress;
  final double currentSaved;
  final double monthsRemaining;

  factory _GoalData.fromMap(Map<String, dynamic> map) {
    return _GoalData(
      goalLabel: GenUiHelpers.safeString(
        map['goalLabel'],
        defaultValue: 'Meta financiera',
      ),
      targetAmount:
          GenUiHelpers.safeDouble(map['targetAmount'], defaultValue: 0),
      targetDate: GenUiHelpers.safeString(map['targetDate'], defaultValue: ''),
      currentProgress:
          GenUiHelpers.safeDouble(map['currentProgress'], defaultValue: 0),
      currentSaved:
          GenUiHelpers.safeDouble(map['currentSaved'], defaultValue: 0),
      monthsRemaining:
          GenUiHelpers.safeDouble(map['monthsRemaining'], defaultValue: 0),
    );
  }
}

class _ProjectionData {
  _ProjectionData({
    required this.currentValue,
    required this.targetValue,
    required this.targetDate,
    required this.scenarios,
    required this.highlightScenario,
  });

  final double currentValue;
  final double targetValue;
  final String targetDate;
  final List<_ScenarioData> scenarios;
  final String highlightScenario;

  factory _ProjectionData.fromMap(Map<String, dynamic> map) {
    final rawScenarios = map['scenarios'];
    final scenarios = (rawScenarios is List ? rawScenarios : const [])
        .whereType<Map>()
        .map((e) => _ScenarioData.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    while (scenarios.length < 3) {
      scenarios.add(_ScenarioData.fallback(scenarios.length));
    }

    return _ProjectionData(
      currentValue:
          GenUiHelpers.safeDouble(map['currentValue'], defaultValue: 0),
      targetValue:
          GenUiHelpers.safeDouble(map['targetValue'], defaultValue: 0),
      targetDate: GenUiHelpers.safeString(map['targetDate'], defaultValue: ''),
      scenarios: scenarios.take(3).toList(),
      highlightScenario: PlanningEnumParser.scenarioLabel(
        map['highlightScenario'] as String?,
      ),
    );
  }
}

class _ScenarioData {
  _ScenarioData({
    required this.label,
    required this.color,
    required this.projectedValue,
    required this.monthlyRequired,
  });

  final String label;
  final String color;
  final double projectedValue;
  final double monthlyRequired;

  factory _ScenarioData.fromMap(Map<String, dynamic> map) {
    return _ScenarioData(
      label: PlanningEnumParser.scenarioLabel(map['label'] as String?),
      color: GenUiHelpers.safeString(map['color'], defaultValue: '#2979FF'),
      projectedValue:
          GenUiHelpers.safeDouble(map['projectedValue'], defaultValue: 0),
      monthlyRequired:
          GenUiHelpers.safeDouble(map['monthlyRequired'], defaultValue: 0),
    );
  }

  factory _ScenarioData.fallback(int index) {
    const labels = ['Conservador', 'Moderado', 'Optimista'];
    const colors = ['#8B95A8', '#2979FF', '#00C853'];
    return _ScenarioData(
      label: labels[index.clamp(0, 2)],
      color: colors[index.clamp(0, 2)],
      projectedValue: 0,
      monthlyRequired: 0,
    );
  }
}

class _MilestoneData {
  _MilestoneData({
    required this.date,
    required this.label,
    required this.targetValue,
    required this.status,
  });

  final String date;
  final String label;
  final double targetValue;
  final String status;

  factory _MilestoneData.fromMap(Map<String, dynamic> map) {
    return _MilestoneData(
      date: GenUiHelpers.safeString(map['date'], defaultValue: ''),
      label: GenUiHelpers.safeString(map['label'], defaultValue: 'Hito'),
      targetValue:
          GenUiHelpers.safeDouble(map['targetValue'], defaultValue: 0),
      status: PlanningEnumParser.milestoneStatus(map['status'] as String?),
    );
  }
}

class _ActionData {
  _ActionData({
    required this.priority,
    required this.title,
    required this.description,
    required this.impact,
    required this.effort,
    this.actionEvent,
  });

  final int priority;
  final String title;
  final String description;
  final String impact;
  final String effort;
  final String? actionEvent;

  factory _ActionData.fromMap(Map<String, dynamic> map) {
    return _ActionData(
      priority:
          GenUiHelpers.safeInt(map['priority'], defaultValue: 1).clamp(1, 3),
      title: GenUiHelpers.safeString(
        map['title'],
        defaultValue: 'Acción recomendada',
      ),
      description:
          GenUiHelpers.safeString(map['description'], defaultValue: ''),
      impact: PlanningEnumParser.impact(map['impact'] as String?),
      effort: PlanningEnumParser.effort(map['effort'] as String?),
      actionEvent: map['actionEvent'] as String?,
    );
  }
}

class _GapData {
  _GapData({
    required this.currentMonthlyContribution,
    required this.requiredMonthlyContribution,
    required this.gap,
    required this.yearsToGoalAtCurrentRate,
    required this.yearsToGoalIfGapClosed,
    required this.message,
  });

  final double currentMonthlyContribution;
  final double requiredMonthlyContribution;
  final double gap;
  final double yearsToGoalAtCurrentRate;
  final double yearsToGoalIfGapClosed;
  final String message;

  factory _GapData.fromMap(Map<String, dynamic> map) {
    return _GapData(
      currentMonthlyContribution: GenUiHelpers.safeDouble(
        map['currentMonthlyContribution'],
        defaultValue: 0,
      ),
      requiredMonthlyContribution: GenUiHelpers.safeDouble(
        map['requiredMonthlyContribution'],
        defaultValue: 0,
      ),
      gap: GenUiHelpers.safeDouble(map['gap'], defaultValue: 0),
      yearsToGoalAtCurrentRate: GenUiHelpers.safeDouble(
        map['yearsToGoalAtCurrentRate'],
        defaultValue: 0,
      ),
      yearsToGoalIfGapClosed: GenUiHelpers.safeDouble(
        map['yearsToGoalIfGapClosed'],
        defaultValue: 0,
      ),
      message: GenUiHelpers.safeString(map['message'], defaultValue: ''),
    );
  }
}

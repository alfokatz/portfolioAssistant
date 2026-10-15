import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/view/goals_verdict.dart';

import 'goal_detail_screen_test.dart' show goalFixture, loadSpanish;

/// Una meta con su progreso armado a mano (la frase solo usa la etiqueta de
/// la meta y los números del progreso).
({UserGoal goal, GoalProgress progress}) _g(
  GoalProgressStatus status, {
  String label = 'Auto',
  double monthly = 500,
  double required = 600,
  double saved = 1000,
  double target = 10000,
}) => (
  goal: goalFixture(label: label),
  progress: GoalProgress(
    status: status,
    saved: saved,
    expected: saved,
    target: target,
    plannedMonthly: monthly,
    requiredMonthlyNow: required,
    monthsElapsed: 1,
    monthsRemaining: 12,
  ),
);

void main() {
  setUpAll(loadSpanish);

  test('nothing active and nothing achieved → no verdict (empty state)', () {
    expect(GoalsVerdict.of([], achieved: 0), isNull);
  });

  test('all achieved → Porty celebrates', () {
    final v = GoalsVerdict.of([], achieved: 2)!;
    expect(v.mood, PortyAvatarState.answered);
    expect(v.message, contains('Cumpliste'));
  });

  test('on track: the monthly total, and the totals as footnote', () {
    final v =
        GoalsVerdict.of([
          _g(GoalProgressStatus.onTrack, monthly: 400),
          _g(GoalProgressStatus.justStarted, label: 'Viaje', monthly: 200),
        ], achieved: 0)!;
    expect(v.mood, PortyAvatarState.answered);
    expect(v.message, contains('2 metas'));
    expect(v.message, contains(QaFormat.money(600)));
    expect(v.footnote, contains(QaFormat.money(20000)));
  });

  test('a goal behind wins: the one that needs the most, Porty concerned', () {
    final v =
        GoalsVerdict.of([
          _g(GoalProgressStatus.ahead, label: 'Fondo'),
          _g(GoalProgressStatus.behind, label: 'Viaje', required: 900),
          _g(GoalProgressStatus.behind, label: 'Auto', required: 1500),
        ], achieved: 0)!;
    expect(v.mood, PortyAvatarState.concerned);
    expect(v.message, startsWith('2 metas'));
    expect(v.message, contains('Auto'));
    expect(v.message, contains(QaFormat.money(1500)));
  });

  test('overdue beats behind; one goal → no totals line', () {
    final v =
        GoalsVerdict.of([
          _g(GoalProgressStatus.behind, label: 'Auto'),
          _g(GoalProgressStatus.overdue, label: 'Viaje', saved: 7000),
        ], achieved: 0)!;
    expect(v.mood, PortyAvatarState.concerned);
    expect(v.message, startsWith('Viaje'));
    expect(v.message, contains(QaFormat.money(3000)));
    final one = GoalsVerdict.of([_g(GoalProgressStatus.onTrack)], achieved: 0)!;
    expect(one.footnote, isNull);
  });

  test('all just saved → calm, no celebration yet', () {
    final v =
        GoalsVerdict.of([
          _g(GoalProgressStatus.justStarted),
          _g(GoalProgressStatus.justStarted, label: 'Viaje'),
        ], achieved: 0)!;
    expect(v.mood, PortyAvatarState.idle);
  });

  test('one ahead among several is named', () {
    final v =
        GoalsVerdict.of([
          _g(GoalProgressStatus.onTrack, label: 'Auto'),
          _g(GoalProgressStatus.ahead, label: 'Fondo'),
        ], achieved: 0)!;
    expect(v.message, contains('Fondo va adelantada'));
  });
}

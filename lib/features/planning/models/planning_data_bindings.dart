import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_external_binding_registry.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';

/// Bindings de datos para el flujo de planificación GenUI.
class PlanningDataBindings {
  PlanningDataBindings();

  final totalValue = ValueNotifier<double>(0);
  final monthlyReturnAvg = ValueNotifier<double?>(null);
  final monthlyContribution = ValueNotifier<double>(0);
  final goalLabel = ValueNotifier<String>('');
  final targetAmount = ValueNotifier<double>(0);
  final targetDate = ValueNotifier<String>('');

  final _bindingRegistry = GenUiExternalBindingRegistry();

  static double? computeMonthlyReturnAvg(List<PortfolioHistoryPoint> history) {
    if (history.length < 2) return null;

    final sorted = [...history]..sort((a, b) => a.date.compareTo(b.date));
    final first = sorted.first;
    final last = sorted.last;
    if (first.totalValue <= 0) return null;

    final months = last.date.difference(first.date).inDays / 30.44;
    if (months < 1) return null;

    final totalReturn = last.totalValue / first.totalValue;
    if (totalReturn <= 0) return null;

    return math.pow(totalReturn, 1 / months).toDouble() - 1;
  }

  void updateFromPortfolio({
    PortfolioSummary? summary,
    List<PortfolioHistoryPoint> history = const [],
    double? savedMonthlyContribution,
  }) {
    totalValue.value = summary?.totalValue ?? 0;
    monthlyReturnAvg.value = computeMonthlyReturnAvg(history);

    if (savedMonthlyContribution != null && savedMonthlyContribution > 0) {
      monthlyContribution.value = savedMonthlyContribution;
    }
  }

  void updateGoal({
    String? label,
    double? amount,
    String? date,
  }) {
    if (label != null && label.trim().isNotEmpty) {
      goalLabel.value = label.trim();
    }
    if (amount != null && amount > 0) {
      targetAmount.value = amount;
    }
    if (date != null && date.trim().isNotEmpty) {
      targetDate.value = date.trim();
    }
  }

  void setMonthlyContribution(double amount) {
    monthlyContribution.value = amount;
  }

  JsonMap buildClientDataModelSeed() {
    return {
      'portfolio': {
        'total_value': totalValue.value,
        'monthly_return_avg': monthlyReturnAvg.value,
      },
      'user': {
        'monthly_contribution': monthlyContribution.value,
      },
      'goals': {
        'label': goalLabel.value.isEmpty ? null : goalLabel.value,
        'target_amount': targetAmount.value > 0 ? targetAmount.value : null,
        'target_date': targetDate.value.isEmpty ? null : targetDate.value,
      },
    };
  }

  Map<String, dynamic>? buildGoalPayload() {
    if (goalLabel.value.isEmpty &&
        targetAmount.value <= 0 &&
        targetDate.value.isEmpty) {
      return null;
    }
    return {
      'label': goalLabel.value.isEmpty ? 'Meta financiera' : goalLabel.value,
      'targetAmount': targetAmount.value,
      'targetDate': targetDate.value,
    };
  }

  void bindToDataModel(DataModel dataModel) {
    releaseFromDataModel();
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/portfolio/total_value'),
        source: totalValue,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/portfolio/monthly_return_avg'),
        source: monthlyReturnAvg,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/user/monthly_contribution'),
        source: monthlyContribution,
        twoWay: true,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/goals/label'),
        source: goalLabel,
        twoWay: true,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/goals/target_amount'),
        source: targetAmount,
        twoWay: true,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/goals/target_date'),
        source: targetDate,
        twoWay: true,
      ),
    );
  }

  void releaseFromDataModel() => _bindingRegistry.releaseAll();

  void dispose() {
    _bindingRegistry.detachWithoutRelease();
    totalValue.dispose();
    monthlyReturnAvg.dispose();
    monthlyContribution.dispose();
    goalLabel.dispose();
    targetAmount.dispose();
    targetDate.dispose();
  }
}

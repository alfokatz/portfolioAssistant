import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_external_binding_registry.dart';
import 'package:portfolio_assistant/features/investment/utils/ticker_sector_map.dart';

/// Bindings de datos para el flujo de inversión GenUI.
class InvestmentDataBindings {
  InvestmentDataBindings();

  final riskProfile = ValueNotifier<double?>(null);
  final availableBudget = ValueNotifier<double>(0);
  final sectors = ValueNotifier<Map<String, double>>({});
  final concentration = ValueNotifier<Map<String, double>>({});
  final marketSentiment = ValueNotifier<String>('neutral');

  final _bindingRegistry = GenUiExternalBindingRegistry();

  static final _budgetPattern = RegExp(
    r'\$?\s*(\d[\d,]*(?:\.\d+)?)\s*(k|K|mil|miles)?',
  );

  void updateFromSummary(PortfolioSummary? summary) {
    if (summary == null || summary.valuations.isEmpty) {
      sectors.value = {};
      concentration.value = {};
      return;
    }

    final total = summary.totalValue;
    final tickerWeights = <String, double>{};
    for (final v in summary.valuations) {
      final weight = total > 0 ? v.marketValue / total : 0.0;
      tickerWeights[v.position.ticker] = weight;
    }

    concentration.value = tickerWeights;
    sectors.value = TickerSectorMap.sectorWeightsFromTickers(tickerWeights);
  }

  void setRiskProfile(double? value) {
    riskProfile.value = value;
  }

  void parseBudgetFromMessage(String message) {
    final match = _budgetPattern.firstMatch(message);
    if (match == null) return;

    var amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
    if (amount == null) return;

    final suffix = match.group(2)?.toLowerCase();
    if (suffix == 'k' || suffix == 'mil' || suffix == 'miles') {
      if (amount < 10000) amount *= 1000;
    }
    availableBudget.value = amount;
  }

  JsonMap buildClientDataModelSeed() {
    return {
      'user': {
        'risk_profile': riskProfile.value,
        'available_budget': availableBudget.value,
      },
      'portfolio': {
        'sectors': sectors.value,
        'concentration': concentration.value,
      },
      'market': {
        'sentiment': marketSentiment.value,
      },
    };
  }

  void bindToDataModel(DataModel dataModel) {
    releaseFromDataModel();
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/user/risk_profile'),
        source: riskProfile,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/user/available_budget'),
        source: availableBudget,
        twoWay: true,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/portfolio/sectors'),
        source: sectors,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/portfolio/concentration'),
        source: concentration,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/market/sentiment'),
        source: marketSentiment,
      ),
    );
  }

  void releaseFromDataModel() => _bindingRegistry.releaseAll();

  void dispose() {
    _bindingRegistry.detachWithoutRelease();
    riskProfile.dispose();
    availableBudget.dispose();
    sectors.dispose();
    concentration.dispose();
    marketSentiment.dispose();
  }
}

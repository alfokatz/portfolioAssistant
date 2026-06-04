import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_external_binding_registry.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';

/// ValueNotifiers enlazados al DataModel de GenUI vía paths externos.
class PortfolioDataBindings {
  PortfolioDataBindings();

  final totalValue = ValueNotifier<double>(0);
  final totalGainLoss = ValueNotifier<double>(0);
  final totalGainLossPct = ValueNotifier<double>(0);
  final lastUpdated = ValueNotifier<String>(
    DateTime.now().toUtc().toIso8601String(),
  );
  final tickers = ValueNotifier<List<String>>([]);

  final Map<String, ValueNotifier<double>> _currentPrices = {};
  final Map<String, ValueNotifier<double>> _gainLosses = {};
  final Map<String, ValueNotifier<double>> _shares = {};

  final _bindingRegistry = GenUiExternalBindingRegistry();

  void updateFromSummary(PortfolioSummary? summary) {
    if (summary == null) {
      totalValue.value = 0;
      totalGainLoss.value = 0;
      totalGainLossPct.value = 0;
      tickers.value = [];
      lastUpdated.value = DateTime.now().toUtc().toIso8601String();
      return;
    }

    totalValue.value = summary.totalValue;
    totalGainLoss.value = summary.totalPnlAbsolute;
    totalGainLossPct.value = summary.totalPnlPercent;
    tickers.value = summary.valuations
        .map((v) => v.position.ticker.toUpperCase())
        .toSet()
        .toList()
      ..sort();
    lastUpdated.value = DateTime.now().toUtc().toIso8601String();

    final tickerSet = summary.valuations.map((v) => v.position.ticker).toSet();
    for (final ticker in tickerSet) {
      _currentPrices.putIfAbsent(ticker, () => ValueNotifier(0));
      _gainLosses.putIfAbsent(ticker, () => ValueNotifier(0));
      _shares.putIfAbsent(ticker, () => ValueNotifier(0));
    }

    for (final valuation in summary.valuations) {
      final ticker = valuation.position.ticker;
      _currentPrices[ticker]!.value = valuation.currentPrice;
      _gainLosses[ticker]!.value = valuation.pnlAbsolute;
      _shares[ticker]!.value = valuation.position.quantity;
    }
  }

  JsonMap buildClientDataModelSeed(PortfolioSummary? summary) {
    if (summary == null) {
      return {
        'portfolio': {
          'total_value': 0,
          'total_gain_loss': 0,
          'total_gain_loss_pct': 0,
          'last_updated': lastUpdated.value,
          'tickers': <String>[],
        },
        'assets': <String, Object?>{},
      };
    }

    final assets = <String, Object?>{};
    for (final valuation in summary.valuations) {
      final ticker = valuation.position.ticker;
      assets[ticker] = {
        'current_price': valuation.currentPrice,
        'gain_loss': valuation.pnlAbsolute,
        'shares': valuation.position.quantity,
      };
    }

    return {
      'portfolio': {
        'total_value': summary.totalValue,
        'total_gain_loss': summary.totalPnlAbsolute,
        'total_gain_loss_pct': summary.totalPnlPercent,
        'last_updated': lastUpdated.value,
        'tickers': tickers.value,
      },
      'assets': assets,
    };
  }

  List<double> sparklineFor({
    required String ticker,
    required PortfolioSummary summary,
  }) {
    PositionValuation? valuation;
    for (final v in summary.valuations) {
      if (v.position.ticker == ticker) {
        valuation = v;
        break;
      }
    }
    if (valuation == null) return const [0, 0];
    return HomeChartUtils.sparklineFromPrices(
      purchasePrice: valuation.position.purchasePrice,
      currentPrice: valuation.currentPrice,
      pointCount: 7,
    );
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
        path: DataPath('/portfolio/total_gain_loss'),
        source: totalGainLoss,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/portfolio/total_gain_loss_pct'),
        source: totalGainLossPct,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/portfolio/last_updated'),
        source: lastUpdated,
      ),
    );
    _bindingRegistry.add(
      dataModel.bindExternalState(
        path: DataPath('/portfolio/tickers'),
        source: tickers,
      ),
    );

    for (final entry in _currentPrices.entries) {
      final ticker = entry.key;
      _bindingRegistry.add(
        dataModel.bindExternalState(
          path: DataPath('/assets/$ticker/current_price'),
          source: entry.value,
        ),
      );
    }
    for (final entry in _gainLosses.entries) {
      final ticker = entry.key;
      _bindingRegistry.add(
        dataModel.bindExternalState(
          path: DataPath('/assets/$ticker/gain_loss'),
          source: entry.value,
        ),
      );
    }
    for (final entry in _shares.entries) {
      final ticker = entry.key;
      _bindingRegistry.add(
        dataModel.bindExternalState(
          path: DataPath('/assets/$ticker/shares'),
          source: entry.value,
        ),
      );
    }
  }

  void releaseFromDataModel() => _bindingRegistry.releaseAll();

  void dispose() {
    _bindingRegistry.detachWithoutRelease();
    totalValue.dispose();
    totalGainLoss.dispose();
    totalGainLossPct.dispose();
    lastUpdated.dispose();
    tickers.dispose();
    for (final n in _currentPrices.values) {
      n.dispose();
    }
    for (final n in _gainLosses.values) {
      n.dispose();
    }
    for (final n in _shares.values) {
      n.dispose();
    }
  }
}

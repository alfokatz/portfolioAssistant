import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';

/// Un link para abrir la posición en el bróker de donde vino. Porty nunca
/// opera: el usuario compra o vende allá y la próxima sincronización lo
/// trae.
class BrokerLink {
  const BrokerLink({
    required this.broker,
    required this.url,
    required this.instrumentPage,
  });

  /// El nombre del bróker ("eToro", "Interactive Brokers").
  final String broker;
  final Uri url;

  /// true: la página de ese instrumento. false: la web del bróker (los que
  /// llegan por SnapTrade no tienen un link por acción).
  final bool instrumentPage;
}

abstract final class BrokerLinks {
  /// `AAPL` → etoro.com/markets/aapl. El ticker de eToro es su símbolo
  /// (sin `.US`); las criptos pueden venir como `BTC-USD`.
  static Uri? etoro(String ticker) {
    final symbol = _withoutUsd(ticker).toLowerCase();
    if (!RegExp(r'^[a-z0-9.\-]+$').hasMatch(symbol)) return null;
    return Uri.https('www.etoro.com', '/markets/$symbol');
  }

  /// `BTC-USD` → el par spot contra USDT en Binance.
  static Uri? binance(String ticker) {
    final base = _withoutUsd(ticker).toUpperCase();
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(base)) return null;
    return Uri.https('www.binance.com', '/en/trade/${base}_USDT', {
      'type': 'spot',
    });
  }

  /// Los links de una posición según de dónde vienen sus compras
  /// ([sources], sin `manual`). Por SnapTrade solo si hay un único bróker
  /// importado con web: con varios no sabemos de cuál vino.
  static List<BrokerLink> forPosition({
    required String ticker,
    required Set<PositionSource> sources,
    List<SnaptradeBrokerage> snaptradeImported = const [],
  }) {
    final links = <BrokerLink>[];
    if (sources.contains(PositionSource.etoro)) {
      final url = etoro(ticker);
      if (url != null) {
        links.add(BrokerLink(broker: 'eToro', url: url, instrumentPage: true));
      }
    }
    if (sources.contains(PositionSource.binance)) {
      final url = binance(ticker);
      if (url != null) {
        links.add(
          BrokerLink(broker: 'Binance', url: url, instrumentPage: true),
        );
      }
    }
    if (sources.contains(PositionSource.snaptrade) &&
        snaptradeImported.length == 1) {
      final b = snaptradeImported.single;
      if (b.url != null) {
        links.add(
          BrokerLink(broker: b.name, url: b.url!, instrumentPage: false),
        );
      }
    }
    return links;
  }

  static String _withoutUsd(String ticker) {
    final t = ticker.trim();
    return t.toUpperCase().endsWith('-USD') ? t.substring(0, t.length - 4) : t;
  }
}

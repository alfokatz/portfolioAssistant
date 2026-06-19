import 'package:portfolio_assistant/features/assistant/modes/invest/sector_display_name.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/ticker_sector_map.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/yahoo_sector_client.dart';

/// Resuelve sectores en español: mapa estático → Yahoo Finance → Sin clasificar.
abstract final class SectorResolver {
  static Future<Map<String, String>> resolveForTickers(
    Iterable<String> tickers, {
    YahooSectorClient? yahooClient,
  }) async {
    final client = yahooClient ?? YahooSectorClient();
    final unique = tickers.map((t) => t.toUpperCase()).toSet();
    final needsYahoo = <String>[];
    final resolved = <String, String>{};

    for (final ticker in unique) {
      final fromMap = sectorForTicker(ticker);
      if (fromMap != null) {
        resolved[ticker] = SectorDisplayName.fromRaw(fromMap);
      } else {
        needsYahoo.add(ticker);
      }
    }

    if (needsYahoo.isNotEmpty) {
      try {
        final fromYahoo = await client.fetchSectors(needsYahoo);
        for (final ticker in needsYahoo) {
          resolved[ticker] = SectorDisplayName.fromRaw(fromYahoo[ticker]);
        }
      } catch (_) {
        for (final ticker in needsYahoo) {
          resolved[ticker] = SectorDisplayName.unclassified;
        }
      }
    }

    return resolved;
  }
}

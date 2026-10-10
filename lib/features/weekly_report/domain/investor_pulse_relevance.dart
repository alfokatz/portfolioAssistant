import 'package:portfolio_assistant/features/weekly_report/domain/investor_pulse_item.dart';
import 'package:portfolio_assistant/infraestructure/repositories/google_news_rss_repository_impl.dart';

/// Un ítem de super investors con las acciones de la cartera que toca.
class RelatedPulseItem {
  const RelatedPulseItem({required this.item, required this.relatedTickers});

  final InvestorPulseItem item;
  final List<String> relatedTickers;

  bool get isRelevant => relatedTickers.isNotEmpty;
}

/// Qué ítems de la semana tocan la cartera del usuario y en qué orden van al
/// informe: primero los que nombran algo que tiene, después el resto en el
/// orden del servidor (presentaciones antes que noticias).
abstract final class InvestorPulseRelevance {
  /// Como mucho por inversor: que nadie acapare el bloque.
  static const maxPerInvestor = 2;

  /// [holdings]: ticker → nombre de la compañía (`null` si no se conoce).
  static List<RelatedPulseItem> rank(
    List<InvestorPulseItem> items, {
    required Map<String, String?> holdings,
    required int limit,
  }) {
    final matchers = {
      for (final MapEntry(key: ticker, value: name) in holdings.entries)
        ticker: _matchersFor(ticker, name),
    };
    final related = [
      for (final item in items)
        RelatedPulseItem(
          item: item,
          relatedTickers: [
            for (final MapEntry(key: ticker, value: patterns)
                in matchers.entries)
              if (_mentions(item, ticker, patterns)) ticker,
          ],
        ),
    ];
    // Orden estable: relevantes primero, sin perder el orden del servidor.
    final ordered = [
      ...related.where((r) => r.isRelevant),
      ...related.where((r) => !r.isRelevant),
    ];
    final perInvestor = <String, int>{};
    final out = <RelatedPulseItem>[];
    for (final r in ordered) {
      final n = perInvestor[r.item.investorId] ?? 0;
      if (n >= maxPerInvestor) continue;
      perInvestor[r.item.investorId] = n + 1;
      out.add(r);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Lo que el informe muestra de super investors (puede ser nada):
  /// - lo que toca una acción del usuario (presentación sobre ese ticker o
  ///   titular que la nombra), hasta [maxRelated];
  /// - si no hay nada de eso, como mucho UN movimiento notable: un Schedule
  ///   13D nuevo (más del 5% de una empresa con intención activista; hay
  ///   pocos por trimestre, y las enmiendas no cuentan);
  /// - nunca: presentaciones del inversor sobre su propia empresa ("Icahn
  ///   actualizó su participación en Icahn Enterprises") ni voces del
  ///   mercado que no nombran nada de la cartera.
  static List<RelatedPulseItem> selectForReport(
    List<InvestorPulseItem> items, {
    required Map<String, String?> holdings,
  }) {
    final usable = [
      for (final i in items)
        if (!isSelfFiling(i)) i,
    ];
    final ranked = rank(usable, holdings: holdings, limit: usable.length);
    final related = [
      for (final r in ranked)
        if (r.isRelevant) r,
    ];
    if (related.isNotEmpty) return related.take(maxRelated).toList();
    final notable = ranked.where(
      (r) => !r.item.isMarketVoice && isNotable(r.item),
    );
    return notable.take(1).toList();
  }

  static const maxRelated = 3;

  /// Un 13D nuevo (no una enmienda): participación activista de más del 5%.
  static bool isNotable(InvestorPulseItem item) =>
      item.isFiling &&
      item.action == 'stake' &&
      (item.form ?? '').toUpperCase().contains('13D');

  /// El inversor presentando sobre su propia empresa (o un vehículo
  /// propio): no dice nada del mercado.
  static bool isSelfFiling(InvestorPulseItem item) {
    final issuer = _core(item.issuerName);
    if (!item.isFiling || issuer == null) return false;
    for (final own in [item.organization, item.investorName]) {
      final o = _core(own);
      if (o == null) continue;
      if (issuer.contains(o) || o.contains(issuer)) return true;
    }
    return false;
  }

  /// "ICAHN ENTERPRISES L.P." → "icahn enterprises".
  static String? _core(String? name) {
    if (name == null) return null;
    final c =
        name
            .toLowerCase()
            .replaceAll(
              RegExp(
                r'\b(inc|corp|corporation|co|company|ltd|plc|lp|l\.p|llc|holdings?|group|the)\b\.?',
              ),
              ' ',
            )
            .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    return c.length < 3 ? null : c;
  }

  static bool _mentions(
    InvestorPulseItem item,
    String ticker,
    List<RegExp> patterns,
  ) {
    if (item.isFiling) {
      if (item.issuerTicker == ticker) return true;
      final issuer = item.issuerName;
      // El ticker suelto no sirve contra un nombre de empresa ("LEN" en
      // "LENNAR"): solo el nombre.
      return issuer != null && patterns.skip(1).any((p) => p.hasMatch(issuer));
    }
    final headline = item.headline ?? '';
    return patterns.any((p) => p.hasMatch(headline));
  }

  /// [0] el ticker como palabra en mayúsculas (o con `$`); después el nombre
  /// de la compañía sin "Inc", "Corp"… como palabra, sin importar mayúsculas.
  static List<RegExp> _matchersFor(String ticker, String? name) {
    final escaped = RegExp.escape(ticker);
    final patterns = <RegExp>[
      // Tickers de una letra ("F", "T") se confunden con cualquier cosa: solo
      // con `$`.
      ticker.length < 2
          ? RegExp('\\\$$escaped(?![A-Za-z])')
          : RegExp('(?<![A-Za-z])\\\$?$escaped(?![A-Za-z])'),
    ];
    final core = GoogleNewsRssRepositoryImpl.coreName(name);
    if (core != null && core.length >= 3) {
      patterns.add(
        RegExp(
          '(?<![A-Za-z])${RegExp.escape(core)}(?![A-Za-z])',
          caseSensitive: false,
        ),
      );
    }
    return patterns;
  }
}

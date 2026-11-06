import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';

/// Una posición agregada por ticker, tal como está en `positions`.
class WidgetHolding {
  const WidgetHolding({
    required this.ticker,
    required this.marketValue,
    this.isCrypto = false,
  });

  final String ticker;
  final double marketValue;

  /// Importada de Binance (el criterio de cripto que ya usa la app).
  final bool isCrypto;
}

/// Fecha estimada de resultados de un ticker (solo el día).
typedef WidgetEarningsDate = ({String ticker, DateTime date});

/// Conteos para los avisos (fase 2: los da el servidor sin mandar contenido).
/// `null` = no se sabe.
class WidgetTeaserCounts {
  const WidgetTeaserCounts({this.news48, this.news24, this.earnings7});

  final int? news48;
  final int? news24;
  final int? earnings7;
}

enum WidgetPlatform { ios, android }

sealed class SelectedWidgetItem {
  const SelectedWidgetItem(this.ticker);

  final String ticker;
}

class SelectedNews extends SelectedWidgetItem {
  const SelectedNews(super.ticker, this.news);

  final CompanyNewsItem news;
}

class SelectedEarnings extends SelectedWidgetItem {
  const SelectedEarnings(super.ticker, this.date);

  /// Día estimado (año, mes y día; sin hora).
  final DateTime date;
}

class SelectedTeaser {
  const SelectedTeaser({required this.kind, this.count, this.medium = false});

  /// 'news' | 'earnings'.
  final String kind;
  final int? count;
  final bool medium;
}

class WidgetItemsSelection {
  const WidgetItemsSelection({
    required this.items,
    required this.teaser,
    required this.itemsSection,
  });

  /// Ya ordenados y truncados (el aviso cuenta en los 4 del grande).
  final List<SelectedWidgetItem> items;
  final SelectedTeaser? teaser;
  final bool itemsSection;
}

/// Qué muestra "Novedades de tu cartera": puro, sin IA, sin red.
/// Ver docs/specs/home-widget-tech.md Am.4.2.
abstract final class WidgetItemsSelector {
  static const topHoldings = 5;
  static const maxItems = 4;
  static const maxEarnings = 2;
  static const newsWindow = Duration(hours: 48);
  static const futureSlack = Duration(minutes: 5);

  /// Titulares con recomendación directa al lector (revisión de compliance
  /// 2026-11-05). Se descartan, no se reescriben. "Analyst upgrades to Buy"
  /// no entra: informa un hecho.
  static final recommendation = <RegExp>[
    RegExp(r'should you (buy|sell)', caseSensitive: false),
    RegExp(r'(stocks?|shares?) to (buy|sell)', caseSensitive: false),
    RegExp(r'(buy|sell) (now|today|this)', caseSensitive: false),
    RegExp(r'time to (buy|sell)', caseSensitive: false),
    RegExp(r'must[- ](buy|sell)', caseSensitive: false),
    RegExp(r'best .* to (buy|sell)', caseSensitive: false),
    RegExp(r'comprá|vendé|aprovechá', caseSensitive: false),
  ];

  static bool isRecommendation(String headline) =>
      recommendation.any((r) => r.hasMatch(headline));

  /// Titular sin mayúsculas, puntuación ni espacios de más (para dedupe).
  static String normalizeHeadline(String headline) =>
      headline
          .toLowerCase()
          .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  /// Los 5 de más peso sin cripto (empate: ticker alfabético).
  static List<WidgetHolding> universe(List<WidgetHolding> holdings) {
    final eligible = [
      for (final h in holdings)
        if (!h.isCrypto && h.marketValue > 0 && h.ticker.isNotEmpty) h,
    ]..sort((a, b) {
      final byValue = b.marketValue.compareTo(a.marketValue);
      return byValue != 0 ? byValue : a.ticker.compareTo(b.ticker);
    });
    return eligible.take(topHoldings).toList();
  }

  static WidgetItemsSelection select({
    required List<WidgetHolding> holdings,
    required List<CompanyNewsItem> news,
    required List<WidgetEarningsDate> earnings,
    required SubscriptionTier tier,
    required bool teasersEnabled,
    required WidgetPlatform platform,
    required DateTime now,
    WidgetTeaserCounts? teaserCounts,
  }) {
    final top = universe(holdings);
    final weight = {for (final h in top) h.ticker.toUpperCase(): h.marketValue};

    final earningsItems = <SelectedEarnings>[];
    if (PlanMatrix.allows(tier, PlanFeature.earnings)) {
      final today = DateTime(now.year, now.month, now.day);
      final last = DateTime(now.year, now.month, now.day + 6);
      final inWeek = <SelectedEarnings>[];
      final seen = <String>{};
      for (final e in earnings) {
        final key = e.ticker.toUpperCase();
        if (!weight.containsKey(key) || !seen.add(key)) continue;
        final day = DateTime(e.date.year, e.date.month, e.date.day);
        if (day.isBefore(today) || day.isAfter(last)) continue;
        inWeek.add(SelectedEarnings(e.ticker, day));
      }
      inWeek.sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return weight[b.ticker.toUpperCase()]!.compareTo(
          weight[a.ticker.toUpperCase()]!,
        );
      });
      earningsItems.addAll(inWeek.take(maxEarnings));
    }

    final newsAllowed = PlanMatrix.allowsNewsFor(tier, held: true);
    final newsItems = <SelectedNews>[];
    if (newsAllowed) {
      final oldest = now.subtract(newsWindow);
      final newest = now.add(futureSlack);
      final latest = <String, CompanyNewsItem>{};
      for (final n in news) {
        final key = n.ticker.toUpperCase();
        if (!weight.containsKey(key)) continue;
        if (n.publishedAt.isBefore(oldest) || n.publishedAt.isAfter(newest)) {
          continue;
        }
        if (n.headline.trim().isEmpty || isRecommendation(n.headline)) continue;
        final current = latest[key];
        if (current == null || n.publishedAt.isAfter(current.publishedAt)) {
          latest[key] = n;
        }
      }
      final ordered =
          latest.entries.toList()..sort((a, b) {
            final byWeight = weight[b.key]!.compareTo(weight[a.key]!);
            return byWeight != 0
                ? byWeight
                : b.value.publishedAt.compareTo(a.value.publishedAt);
          });
      // Dedupe por titular normalizado: ya viene por peso, queda el primero.
      final headlines = <String>{};
      for (final e in ordered) {
        if (headlines.add(normalizeHeadline(e.value.headline))) {
          newsItems.add(SelectedNews(e.value.ticker, e.value));
        }
      }
    }

    final teaser = _teaser(
      tier: tier,
      enabled: teasersEnabled,
      platform: platform,
      counts: teaserCounts,
      hasEligible: top.isNotEmpty,
    );
    final cap = teaser != null ? maxItems - 1 : maxItems;
    final items =
        <SelectedWidgetItem>[...earningsItems, ...newsItems].take(cap).toList();

    return WidgetItemsSelection(
      items: items,
      teaser: teaser,
      itemsSection: (newsAllowed && top.isNotEmpty) || teaser != null,
    );
  }

  static SelectedTeaser? _teaser({
    required SubscriptionTier tier,
    required bool enabled,
    required WidgetPlatform platform,
    required WidgetTeaserCounts? counts,
    required bool hasEligible,
  }) {
    if (!enabled || !hasEligible) return null;
    if (tier == SubscriptionTier.free) {
      final n48 = counts?.news48;
      if (n48 != null) {
        if (n48 <= 0) return null;
        return SelectedTeaser(
          kind: 'news',
          count: n48,
          medium: (counts?.news24 ?? 0) > 0,
        );
      }
      // Fase 1: sin conteo. Solo Android, con el texto sin número.
      return platform == WidgetPlatform.android
          ? const SelectedTeaser(kind: 'news')
          : null;
    }
    if (tier == SubscriptionTier.premium) {
      final n7 = counts?.earnings7;
      if (n7 != null && n7 > 0) {
        return SelectedTeaser(kind: 'earnings', count: n7);
      }
    }
    return null;
  }

  /// FNV-1a de 32 bits en 8 hex: id opaco del ítem.
  static String itemId(String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash ^= unit & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
      if (unit > 0xff) {
        hash ^= (unit >> 8) & 0xff;
        hash = (hash * 0x01000193) & 0xffffffff;
      }
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String newsId(String ticker, String url) =>
      itemId('news|${ticker.toUpperCase()}|$url');

  static String earningsId(String ticker, DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return itemId(
      'earnings|${ticker.toUpperCase()}|${date.year}-${two(date.month)}-${two(date.day)}',
    );
  }
}

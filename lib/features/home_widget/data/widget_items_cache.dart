import 'dart:convert';

import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un ítem guardado en la caché privada. A diferencia del snapshot que lee el
/// widget, acá SÍ está la URL del artículo (la usa la hoja "Leer en ...").
class WidgetCachedItem {
  const WidgetCachedItem({
    required this.id,
    required this.kind,
    required this.ticker,
    required this.expiresAt,
    this.headline,
    this.source,
    this.url,
    this.publishedAt,
    this.date,
  });

  factory WidgetCachedItem.fromSelected(SelectedWidgetItem item) =>
      switch (item) {
        SelectedNews(:final news) => WidgetCachedItem(
          id: WidgetItemsSelector.newsId(news.ticker, news.url),
          kind: 'news',
          ticker: news.ticker,
          headline: news.headline,
          source: news.source,
          url: news.url,
          publishedAt: news.publishedAt,
          expiresAt: news.publishedAt.add(WidgetItemsSelector.newsWindow),
        ),
        SelectedEarnings(:final ticker, :final date) => WidgetCachedItem(
          id: WidgetItemsSelector.earningsId(ticker, date),
          kind: 'earnings',
          ticker: ticker,
          date: date,
          expiresAt: DateTime(date.year, date.month, date.day, 23, 59, 59),
        ),
      };

  static WidgetCachedItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final kind = raw['kind'];
    final ticker = raw['ticker'];
    final expires = raw['expires_at'];
    if (id is! String || ticker is! String || expires is! int) return null;
    if (kind != 'news' && kind != 'earnings') return null;
    DateTime? ms(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true) : null;
    final date = raw['date'] is String ? DateTime.tryParse(raw['date']) : null;
    return WidgetCachedItem(
      id: id,
      kind: kind as String,
      ticker: ticker,
      headline: raw['headline'] as String?,
      source: raw['source'] as String?,
      url: raw['url'] as String?,
      publishedAt: ms(raw['published_at']),
      date: date == null ? null : DateTime(date.year, date.month, date.day),
      expiresAt: ms(expires)!,
    );
  }

  final String id;

  /// 'news' | 'earnings'.
  final String kind;
  final String ticker;
  final String? headline;
  final String? source;
  final String? url;
  final DateTime? publishedAt;

  /// Solo resultados: el día estimado.
  final DateTime? date;
  final DateTime expiresAt;

  bool get isNews => kind == 'news';

  bool isLive(DateTime now) => now.isBefore(expiresAt);

  SelectedWidgetItem toSelected() =>
      isNews
          ? SelectedNews(
            ticker,
            CompanyNewsItem(
              ticker: ticker,
              headline: headline ?? '',
              summary: '',
              url: url ?? '',
              source: source ?? '',
              publishedAt: publishedAt ?? expiresAt,
            ),
          )
          : SelectedEarnings(ticker, date!);

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'ticker': ticker,
    if (headline != null) 'headline': headline,
    if (source != null) 'source': source,
    if (url != null) 'url': url,
    if (publishedAt != null)
      'published_at': publishedAt!.toUtc().millisecondsSinceEpoch,
    if (date != null)
      'date':
          '${date!.year.toString().padLeft(4, '0')}-'
          '${date!.month.toString().padLeft(2, '0')}-'
          '${date!.day.toString().padLeft(2, '0')}',
    'expires_at': expiresAt.toUtc().millisecondsSinceEpoch,
  };
}

/// Lo último que se trajo para un usuario.
class WidgetItemsCacheEntry {
  const WidgetItemsCacheEntry({
    required this.uid,
    required this.checkedAt,
    required this.tier,
    required this.top,
    required this.teasersEnabled,
    required this.itemsSection,
    required this.items,
    this.planUntil,
    this.teaser,
  });

  static WidgetItemsCacheEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['uid'];
    final checked = raw['checked_at'];
    if (uid is! String || checked is! int) return null;
    final teaserRaw = raw['teaser'];
    return WidgetItemsCacheEntry(
      uid: uid,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(checked, isUtc: true),
      tier: '${raw['tier'] ?? 'free'}',
      top: '${raw['top'] ?? ''}',
      teasersEnabled: raw['teasers'] == true,
      itemsSection: raw['section'] == true,
      planUntil:
          raw['plan_until'] is int
              ? DateTime.fromMillisecondsSinceEpoch(
                raw['plan_until'] as int,
                isUtc: true,
              )
              : null,
      items: [
        for (final i in (raw['items'] as List? ?? const []))
          if (WidgetCachedItem.fromJson(i) case final item?) item,
      ],
      teaser:
          teaserRaw is Map
              ? SelectedTeaser(
                kind: '${teaserRaw['kind']}',
                count: teaserRaw['count'] as int?,
                medium: teaserRaw['medium'] == true,
              )
              : null,
    );
  }

  final String uid;
  final DateTime checkedAt;
  final String tier;

  /// Los tickers del top 5, ordenados y separados por coma: si cambia, hay
  /// que volver a pedir.
  final String top;
  final bool teasersEnabled;
  final bool itemsSection;
  final DateTime? planUntil;
  final List<WidgetCachedItem> items;
  final SelectedTeaser? teaser;

  /// Lo que no venció todavía.
  List<WidgetCachedItem> liveItems(DateTime now) => [
    for (final i in items)
      if (i.isLive(now)) i,
  ];

  /// La selección para armar el snapshot en [now], sin lo vencido. Si ya
  /// venció todo, pasa los vencidos igual: el nativo los filtra y muestra
  /// "todo venció" en vez de "no encontramos novedades".
  WidgetItemsSelection selection(DateTime now) {
    final live = liveItems(now);
    return WidgetItemsSelection(
      items: [for (final i in live.isEmpty ? items : live) i.toSelected()],
      teaser: teaser,
      itemsSection: itemsSection,
    );
  }

  Map<String, Object?> toJson() => {
    'uid': uid,
    'checked_at': checkedAt.toUtc().millisecondsSinceEpoch,
    'tier': tier,
    'top': top,
    'teasers': teasersEnabled,
    'section': itemsSection,
    'plan_until': planUntil?.toUtc().millisecondsSinceEpoch,
    'items': [for (final i in items) i.toJson()],
    if (teaser != null)
      'teaser': {
        'kind': teaser!.kind,
        'count': teaser!.count,
        'medium': teaser!.medium,
      },
  };
}

/// Caché PRIVADA de los ítems (`SharedPreferences` de la app, no el
/// almacenamiento compartido con el widget). Se borra al cerrar sesión.
class WidgetItemsCache {
  const WidgetItemsCache(this._prefs);

  static const key = 'widget_items_cache_v1';

  /// Fechas estimadas de resultados por ticker (caché de 12 h).
  static const earningsKey = 'widget_earnings_cache_v1';

  /// Cuándo se loguearon por última vez las novedades dibujadas.
  static const renderLoggedKey = 'widget_items_render_logged_at';

  final SharedPreferences _prefs;

  /// Solo si es del usuario [uid]; si no, como si no hubiera.
  WidgetItemsCacheEntry? read({required String uid}) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final entry = WidgetItemsCacheEntry.fromJson(jsonDecode(raw));
      return entry != null && entry.uid == uid ? entry : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(WidgetItemsCacheEntry entry) =>
      _prefs.setString(key, jsonEncode(entry.toJson()));

  Future<void> clear() async {
    await clearItems();
    await _prefs.remove(renderLoggedKey);
  }

  /// Solo los datos (v2 apagado): conserva cuándo se logueó lo dibujado,
  /// así no se repite `widget_items_rendered`.
  Future<void> clearItems() async {
    await _prefs.remove(key);
    await _prefs.remove(earningsKey);
  }
}

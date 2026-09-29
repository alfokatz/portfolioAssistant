import 'dart:io' show HttpDate;

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:xml/xml.dart';

/// Titulares de Google News vía su feed RSS de búsqueda — gratis y sin key.
///
/// Se eligió sobre la búsqueda web de OpenAI (probada: con gpt-4.1-mini
/// hace una sola búsqueda, trae 1-2 notas y llega a inventar URLs de
/// Reuters) y sobre Finnhub solo (~85% sindicado de Yahoo): Google News
/// agrega Reuters, CNBC, WSJ, Bloomberg, NYT, AP y comunicados oficiales,
/// ya ordenados por relevancia, y los links son reales (redirects de
/// news.google.com que el navegador resuelve al artículo).
///
/// No trae imagen ni resumen: la card muestra el logo del medio y el
/// titular. El request sale desde cada dispositivo (no hay key compartida
/// que agotar), y el fetcher lo cachea 10 min por ticker.
///
/// Nunca lanza: red/HTTP/XML inválido → `Left`; sin resultados → `Right([])`.
class GoogleNewsRssRepositoryImpl implements CompanyNewsRepository {
  GoogleNewsRssRepositoryImpl({Dio? dio, this.companyNameOf})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              headers: {'User-Agent': 'Mozilla/5.0 (Porty)'},
              responseType: ResponseType.plain,
              validateStatus: (s) => s != null && s < 500,
            ),
          );

  final Dio _dio;

  /// Nombre de la compañía para armar la búsqueda ("NVIDIA stock"): buscar
  /// por ticker solo mezcla homónimos ("KO" = nocaut).
  final Future<String?> Function(String ticker)? companyNameOf;

  static const _endpoint = 'https://news.google.com/rss/search';

  @override
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
  }) async {
    final upper = ticker.toUpperCase();
    try {
      final name = await companyNameOf?.call(upper);
      final feeds = await Future.wait(
        searchQueries(upper, name).map((q) => _search(q, upper)),
      );
      final ok = [
        for (final f in feeds)
          if (f != null) f,
      ];
      if (ok.isEmpty) return Left(HttpError(code: 'google_news_failed'));
      return Right(interleave(ok).take(limit).toList());
    } catch (_) {
      return Left(HttpError(code: 'unknown'));
    }
  }

  Future<List<CompanyNewsItem>?> _search(String query, String ticker) async {
    try {
      final response = await _dio.get<String>(
        _endpoint,
        queryParameters: {
          'q': '$query when:7d',
          'hl': 'en-US',
          'gl': 'US',
          'ceid': 'US:en',
        },
      );
      if (response.statusCode != 200 || response.data == null) return null;
      return parse(response.data!, ticker);
    } catch (_) {
      return null;
    }
  }

  /// Dos búsquedas complementarias (probadas con NVDA/AAPL/KO):
  /// - `"Nombre"` trae los HECHOS de la semana (recompras, juicios,
  ///   lanzamientos) pero mezcla consumo ("review del iPhone");
  /// - `Nombre stock` trae el ángulo de mercado pero sesga a notas de
  ///   opinión ("Can It Climb Further?").
  /// Juntas y rankeadas cubren ambos. Sin nombre, solo `TICKER stock`
  /// (buscar el ticker suelto mezcla homónimos: "KO" = nocaut).
  static List<String> searchQueries(String ticker, String? companyName) {
    final core = coreName(companyName);
    return core == null ? ['$ticker stock'] : ['"$core"', '$core stock'];
  }

  /// Intercala feeds preservando el orden de relevancia de cada uno, sin
  /// repetir URLs.
  static List<CompanyNewsItem> interleave(List<List<CompanyNewsItem>> feeds) {
    final out = <CompanyNewsItem>[];
    final seen = <String>{};
    final longest = feeds.fold<int>(0, (m, f) => f.length > m ? f.length : m);
    for (var i = 0; i < longest; i++) {
      for (final feed in feeds) {
        if (i < feed.length && seen.add(feed[i].url)) out.add(feed[i]);
      }
    }
    return out;
  }

  /// "NVIDIA Corp" → "NVIDIA"; "Coca-Cola Co" → "Coca-Cola".
  static String? coreName(String? companyName) {
    final core =
        companyName
            ?.replaceAll(
              RegExp(
                r'\b(inc|corp|corporation|co|company|ltd|plc|holdings|group|class [ab])\b\.?',
                caseSensitive: false,
              ),
              '',
            )
            .replaceAll(RegExp(r'[,.]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    return core == null || core.isEmpty ? null : core;
  }

  /// Parsea el RSS en el orden de Google (que ya es por relevancia). Items
  /// sin título, link o fecha se descartan.
  static List<CompanyNewsItem> parse(String body, String ticker) {
    final doc = XmlDocument.parse(body);
    final out = <CompanyNewsItem>[];
    for (final item in doc.findAllElements('item')) {
      final rawTitle = item.getElement('title')?.innerText.trim() ?? '';
      final link = item.getElement('link')?.innerText.trim() ?? '';
      final pub = item.getElement('pubDate')?.innerText.trim();
      final sourceEl = item.getElement('source');
      final source = sourceEl?.innerText.trim() ?? '';
      if (rawTitle.isEmpty || !link.startsWith('https://') || pub == null) {
        continue;
      }
      final DateTime published;
      try {
        published = HttpDate.parse(pub);
      } catch (_) {
        continue;
      }
      out.add(
        CompanyNewsItem(
          ticker: ticker,
          headline: _stripSource(rawTitle, source),
          summary: '',
          url: link,
          source: source,
          publishedAt: published,
          sourceDomain: _domain(sourceEl?.getAttribute('url')),
        ),
      );
    }
    return out;
  }

  /// Google agrega " - Reuters" al final de cada título.
  static String _stripSource(String title, String source) {
    if (source.isEmpty) return title;
    final suffix = ' - $source';
    return title.endsWith(suffix)
        ? title.substring(0, title.length - suffix.length).trim()
        : title;
  }

  static String? _domain(String? url) {
    if (url == null) return null;
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

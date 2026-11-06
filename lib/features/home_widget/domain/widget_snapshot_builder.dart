import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_launch.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_phrase.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_texts.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Arma el [WidgetSnapshot] de cada estado. Puro: la hora, el idioma y los
/// textos entran por parámetro (también corre en el isolate de fondo).
abstract final class WidgetSnapshotBuilder {
  static const _staleAfter = Duration(hours: 24);

  /// Claves de `labels` que usa el nativo (`message` solo en los estados
  /// sin cartera).
  static Map<String, String> _labels(WidgetTexts t, DateTime? dataAsOf) => {
    'period_today': t.get('period_today'),
    'period_last_close': t.get('period_last_close'),
    if (dataAsOf != null) 'stale_date': _staleDate(t, dataAsOf),
    'updated_now': t.get('updated_now'),
    'updated_min': t.get('updated_min'),
    'updated_h': t.get('updated_h'),
    'updated_d': t.get('updated_d'),
    'hidden_amount': t.get('hidden_amount'),
    'hidden_a11y': t.get('hidden_a11y'),
  };

  /// "al 3 nov" / "as of Nov 3", con el día del teléfono.
  static String _staleDate(WidgetTexts t, DateTime dataAsOf) {
    final local = dataAsOf.toLocal();
    return t.get('stale_date', {
      'day': '${local.day}',
      'month': t.months[local.month - 1],
    });
  }

  static WidgetSnapshot signedOut({
    required String lang,
    required DateTime now,
    required WidgetTexts texts,
  }) => WidgetSnapshot(
    state: WidgetSnapshotState.signedOut,
    lang: lang,
    writtenAt: now,
    labels: {'message': texts.get('message_signed_out')},
  );

  static WidgetSnapshot noPortfolio({
    required String lang,
    required DateTime now,
    required WidgetTexts texts,
  }) => WidgetSnapshot(
    state: WidgetSnapshotState.noPortfolio,
    lang: lang,
    writtenAt: now,
    labels: {'message': texts.get('message_no_portfolio')},
  );

  /// El estado con datos. [totalValue] es `summary.totalValue` de la Home.
  /// [dataAsOf] es cuándo se trajeron los precios.
  static WidgetSnapshot ready({
    required double totalValue,
    required PortfolioDayMove move,
    required bool amountsHidden,
    required String lang,
    required DateTime now,
    required DateTime dataAsOf,
    required WidgetTexts texts,
  }) {
    final direction = WidgetDirection.fromPercent(move.percent);
    final isToday = move.period == DayMovePeriod.today;
    // Con montos ocultos el ticker ni se calcula: no llega al almacén.
    final topTicker =
        isToday && !amountsHidden ? move.topContributor?.ticker : null;
    final pctText = AppNumberFormat.percent(move.percent);
    final totalText = AppNumberFormat.money(totalValue);

    return WidgetSnapshot(
      state: WidgetSnapshotState.ready,
      lang: lang,
      writtenAt: now,
      dataAsOf: dataAsOf,
      staleAt: staleAt(dataAsOf, move.period),
      period: move.period.wire,
      amountsHidden: amountsHidden,
      totalText: amountsHidden ? null : totalText,
      changeText:
          amountsHidden ? null : AppNumberFormat.signedMoney(move.absolute),
      changePctText: pctText,
      direction: direction,
      phrase: WidgetPhrase.resolve(
        period: move.period,
        direction: direction,
        topTicker: topTicker,
        texts: texts,
      ),
      phraseStale: WidgetPhrase.stale(texts),
      a11yValue: _a11y(
        texts: texts,
        hidden: amountsHidden,
        period: move.period,
        direction: direction,
        total: totalText,
        pct: AppNumberFormat.percent(move.percent.abs(), signed: false),
      ),
      labels: _labels(texts, dataAsOf),
      questions: [
        for (final id in WidgetQuestionId.values)
          WidgetQuestion(id: id, text: texts.get(id.textKey)),
      ],
    );
  }

  /// Suma el bloque de "Novedades de tu cartera" a un `ready`. [checkedAt] es
  /// la última consulta OK a la fuente; [planUntil], el vencimiento conocido
  /// del plan. Los ítems siguen aunque los montos estén ocultos.
  static WidgetSnapshot withItems({
    required WidgetSnapshot base,
    required WidgetItemsSelection selection,
    required DateTime now,
    required DateTime checkedAt,
    required WidgetTexts texts,
    required WidgetPlatform platform,
    DateTime? planUntil,
  }) {
    if (base.state != WidgetSnapshotState.ready) return base;
    if (!selection.itemsSection) {
      return base.copyWith(
        itemsSection: false,
        itemsCheckedAt: checkedAt,
        planUntil: planUntil,
      );
    }
    return base.copyWith(
      itemsSection: true,
      itemsCheckedAt: checkedAt,
      planUntil: planUntil,
      items: [
        for (final item in selection.items) _item(item, now: now, texts: texts),
      ],
      teaser: _teaser(selection.teaser, texts, platform),
      itemsLabels: itemsLabels(texts),
    );
  }

  /// Los textos del bloque de novedades que arma el nativo.
  static Map<String, String> itemsLabels(WidgetTexts t) => {
    'section': t.get('items_section'),
    'empty': t.get('items_empty'),
    'all_expired': t.get('items_all_expired'),
    'redacted': t.get('items_redacted'),
    'age_min': t.get('age_min'),
    'age_h': t.get('age_h'),
    'age_yesterday': t.get('age_yesterday'),
    'a11y_news': t.get('a11y_news'),
  };

  static WidgetItem _item(
    SelectedWidgetItem item, {
    required DateTime now,
    required WidgetTexts texts,
  }) => switch (item) {
    SelectedNews(:final news) => WidgetItem.news(
      id: WidgetItemsSelector.newsId(news.ticker, news.url),
      ticker: news.ticker,
      source: news.source,
      headline: news.headline,
      publishedAt: news.publishedAt,
      expiresAt: news.publishedAt.add(WidgetItemsSelector.newsWindow),
    ),
    SelectedEarnings(:final date, :final ticker) => WidgetItem.earnings(
      id: WidgetItemsSelector.earningsId(ticker, date),
      ticker: ticker,
      segments: earningsSegments(
        ticker: ticker,
        date: date,
        now: now,
        texts: texts,
      ),
      a11y: texts.get('earnings_date', {
        'ticker': ticker,
        'date': dateLabel(texts, date),
      }),
      expiresAt: earningsExpiry(date),
    ),
  };

  /// Fin del día local de la fecha estimada.
  static DateTime earningsExpiry(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59);

  /// "jue 7 nov" / "Thu, Nov 7".
  static String dateLabel(WidgetTexts t, DateTime date) {
    final weekdays = t.get('weekdays').split(',');
    return t.get('date_format', {
      'weekday': weekdays[date.weekday % 7],
      'day': '${date.day}',
      'month': t.months[date.month - 1],
    });
  }

  /// Hoy / mañana / fecha: el nativo usa el último con `from <= ahora`.
  /// La primera arranca en [now], así que siempre hay una vigente.
  static List<WidgetItemSegment> earningsSegments({
    required String ticker,
    required DateTime date,
    required DateTime now,
    required WidgetTexts texts,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final dayBefore = DateTime(date.year, date.month, date.day - 1);
    final day = DateTime(date.year, date.month, date.day);
    String text(String key) => texts.get(key, {'ticker': ticker});
    final todayText = text('earnings_today');
    final tomorrowText = text('earnings_tomorrow');
    final dateText = texts.get('earnings_date', {
      'ticker': ticker,
      'date': dateLabel(texts, day),
    });
    if (!day.isAfter(today)) {
      return [WidgetItemSegment(from: now, text: todayText)];
    }
    final segments = <WidgetItemSegment>[];
    if (dayBefore.isAfter(today)) {
      segments.add(WidgetItemSegment(from: now, text: dateText));
      segments.add(WidgetItemSegment(from: dayBefore, text: tomorrowText));
    } else {
      segments.add(WidgetItemSegment(from: now, text: tomorrowText));
    }
    segments.add(WidgetItemSegment(from: day, text: todayText));
    return segments;
  }

  static WidgetTeaser? _teaser(
    SelectedTeaser? teaser,
    WidgetTexts t,
    WidgetPlatform platform,
  ) {
    if (teaser == null) return null;
    final platformKey = platform == WidgetPlatform.ios ? 'ios' : 'android';
    final count = teaser.count;
    final text =
        count == null
            ? t.get('teaser_news_android_nocount')
            : t.get(
              'teaser_${teaser.kind}_${platformKey}_${count == 1 ? 'one' : 'other'}',
              {'n': '$count'},
            );
    return WidgetTeaser(
      kind: teaser.kind,
      text: text,
      count: count,
      medium: teaser.medium,
    );
  }

  /// Desde cuándo el widget dibuja "datos viejos" (lo compara el nativo con
  /// la hora). Hoy: lo que pase primero entre 24 h y la próxima medianoche
  /// local (después "hoy" sería falso). Último cierre: 24 h.
  static DateTime staleAt(DateTime dataAsOf, DayMovePeriod period) {
    final local = dataAsOf.toLocal();
    final after24h = local.add(_staleAfter);
    if (period == DayMovePeriod.lastClose) return after24h;
    final midnight = DateTime(local.year, local.month, local.day + 1);
    return midnight.isBefore(after24h) ? midnight : after24h;
  }

  /// Lo que lee el lector de pantalla, armado desde el estado YA ocultado:
  /// con montos ocultos no hay ningún número.
  static String _a11y({
    required WidgetTexts texts,
    required bool hidden,
    required DayMovePeriod period,
    required WidgetDirection direction,
    required String total,
    required String pct,
  }) {
    if (hidden) return texts.get('hidden_a11y');
    return texts.get(
      period == DayMovePeriod.today ? 'a11y_today' : 'a11y_last_close',
      {
        'total': total,
        'direction': texts.get('a11y_${direction.wire}'),
        'pct': pct,
      },
    );
  }
}

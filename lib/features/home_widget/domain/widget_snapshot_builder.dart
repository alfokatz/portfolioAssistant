import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_feed_builder.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_feed_order.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_insight_copy.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_phrase.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_portfolio_facts.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_texts.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Un `ready` armado, con lo que hay que guardar aparte del JSON.
class WidgetReadyBuild {
  const WidgetReadyBuild({
    required this.snapshot,
    required this.feedState,
    required this.questionDrafts,
  });

  final WidgetSnapshot snapshot;

  /// El estado de histéresis a persistir (sin cambios si las posiciones
  /// están ocultas: no hay ids en el JSON).
  final WidgetFeedState feedState;

  /// Las preguntas que quedaron en el snapshot (para la caché privada que
  /// resuelve el `ref` tocado).
  final List<WidgetQuestionDraft> questionDrafts;
}

/// Arma el [WidgetSnapshot] de cada estado. Puro: la hora, el idioma y los
/// textos entran por parámetro (también corre en el isolate de fondo).
///
/// Ningún snapshot lleva montos ni el valor total (docs/specs/home-widget-
/// v2-tech.md §3).
abstract final class WidgetSnapshotBuilder {
  static const _staleAfter = Duration(hours: 24);

  /// Claves de `labels` del bloque v1 (`message` solo en los estados sin
  /// cartera).
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

  /// Los textos del bloque v2 que arma el nativo (siempre todos: el scrub
  /// de posiciones ocultas no los toca).
  static Map<String, String> v2Labels(WidgetTexts t) => {
    'your_portfolio': t.get('your_portfolio'),
    'age_now': t.get('age_now'),
    'age_min': t.get('age_min'),
    'age_h': t.get('age_h'),
    'age_yesterday': t.get('age_yesterday'),
    'age_d': t.get('age_d'),
    'header_one': t.getInbox('title_one'),
    'header_other': t.getInbox('title_many').replaceAll('{count}', '{n}'),
    'header_none': t.get('header_none'),
    'list_title': t.get('list_title'),
    'next': t.get('next'),
    'next_a11y': t.get('next_a11y'),
    'hidden_count_one': t.get('hidden_count_one'),
    'hidden_count_other': t.get('hidden_count_other'),
    'no_news': t.get('no_news'),
    'redacted': t.get('items_redacted'),
    'chart_a11y_intraday': t.get('chart_a11y_intraday'),
    'chart_a11y_days': t.get('chart_a11y_days'),
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

  /// El estado con datos, sin el detalle de estado de histéresis.
  static WidgetSnapshot ready({
    required PortfolioDayMove move,
    required bool positionsHidden,
    required String lang,
    required DateTime now,
    required DateTime dataAsOf,
    required WidgetTexts texts,
    SubscriptionTier tier = SubscriptionTier.free,
    WidgetPlatform platform = WidgetPlatform.android,
    WidgetItemsSelection? selection,
    DateTime? planUntil,
    List<WidgetInsightInput> insights = const [],
    WidgetMoverFact? mover,
    WidgetBiggestFact? biggest,
    WidgetQuestionContext? questionContext,
    WidgetChart? chart,
    WidgetFeedState feedState = const WidgetFeedState(),
  }) =>
      readyBuild(
        move: move,
        positionsHidden: positionsHidden,
        lang: lang,
        now: now,
        dataAsOf: dataAsOf,
        texts: texts,
        tier: tier,
        platform: platform,
        selection: selection,
        planUntil: planUntil,
        insights: insights,
        mover: mover,
        biggest: biggest,
        questionContext: questionContext,
        chart: chart,
        feedState: feedState,
      ).snapshot;

  /// El estado con datos. [move] es la variación del día de la Home;
  /// [dataAsOf] es cuándo se trajeron los precios.
  static WidgetReadyBuild readyBuild({
    required PortfolioDayMove move,
    required bool positionsHidden,
    required String lang,
    required DateTime now,
    required DateTime dataAsOf,
    required WidgetTexts texts,
    SubscriptionTier tier = SubscriptionTier.free,
    WidgetPlatform platform = WidgetPlatform.android,
    WidgetItemsSelection? selection,
    DateTime? planUntil,
    List<WidgetInsightInput> insights = const [],
    WidgetMoverFact? mover,
    WidgetBiggestFact? biggest,
    WidgetQuestionContext? questionContext,
    WidgetChart? chart,
    WidgetFeedState feedState = const WidgetFeedState(),
  }) {
    final direction = WidgetDirection.fromPercent(move.percent);
    final isToday = move.period == DayMovePeriod.today;
    final stale = staleAt(dataAsOf, move.period);
    final pct = AppNumberFormat.percent(move.percent.abs(), signed: false);

    final base = WidgetFeedBuilder.build(
      WidgetFeedInputs(
        tier: tier,
        now: now,
        staleAt: stale,
        period: move.period,
        platform: platform,
        selection: selection,
        insights: insights,
        mover: mover,
        biggest: biggest,
      ),
      texts,
    );

    final ctx =
        questionContext ??
        WidgetQuestionContext(tier: tier, biggestTicker: biggest?.ticker);
    final List<WidgetFeedItem> feed;
    final String? feedRev;
    final WidgetFeedState nextState;
    final WidgetQuestionDraft? head;
    if (positionsHidden) {
      // Ni ids ni textos: solo clase, vencimiento y prioridad. La
      // histéresis no se toca (no hay ids en el JSON).
      feed = [for (final i in base.items) i.hiddenForm];
      feedRev = null;
      nextState = feedState;
      head = null;
    } else {
      final ordered = WidgetFeedOrder.apply(
        ordered: base.items,
        state: feedState,
        now: now,
      );
      feed = ordered.feed;
      feedRev = ordered.feedRev;
      nextState = ordered.state;
      head = feed.isEmpty ? null : base.drafts[feed.first.id];
    }
    final questions = WidgetQuestionsBuilder.build(
      ctx: ctx,
      hidden: positionsHidden,
      head: head,
      texts: texts,
    );

    final snapshot = WidgetSnapshot(
      state: WidgetSnapshotState.ready,
      lang: lang,
      writtenAt: now,
      dataAsOf: dataAsOf,
      staleAt: stale,
      period: move.period.wire,
      changePctText: AppNumberFormat.percent(move.percent),
      direction: direction,
      // Plantilla sin ticker: el bloque v1 nunca nombra una tenencia.
      phrase: WidgetPhrase.resolve(
        period: move.period,
        direction: direction,
        topTicker: null,
        texts: texts,
      ),
      phraseStale: WidgetPhrase.stale(texts),
      a11yValue: texts.get(isToday ? 'a11y_v2_today' : 'a11y_v2_last_close', {
        'direction': texts.get('a11y_${direction.wire}'),
        'pct': pct,
      }),
      labels: _labels(texts, dataAsOf),
      v2: WidgetV2Block(
        positionsHidden: positionsHidden,
        mood: WidgetMood.fromDirection(direction),
        planUntil: planUntil,
        chart: chart,
        feedRev: feedRev,
        feed: feed,
        questions: questions.questions,
        labels: v2Labels(texts),
      ),
    );
    return WidgetReadyBuild(
      snapshot: snapshot,
      feedState: nextState,
      questionDrafts: questions.drafts,
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
}

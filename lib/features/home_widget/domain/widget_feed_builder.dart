import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_insight_copy.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_portfolio_facts.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_texts.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Todo lo que entra al feed. Puro: no lee providers ni red, así corre
/// igual con la app abierta y en el refresco de fondo.
class WidgetFeedInputs {
  const WidgetFeedInputs({
    required this.tier,
    required this.now,
    required this.staleAt,
    required this.period,
    required this.platform,
    this.selection,
    this.insights = const [],
    this.mover,
    this.biggest,
  });

  final SubscriptionTier tier;
  final DateTime now;

  /// Cuándo vencen mover, biggest y teaser.
  final DateTime staleAt;
  final DayMovePeriod period;
  final WidgetPlatform platform;

  /// News, resultados y aviso de plan (`WidgetItemsSelector`, con `cap` 7).
  final WidgetItemsSelection? selection;

  /// Los avisos de la Home, ya ordenados por `score` (≤ 3).
  final List<WidgetInsightInput> insights;
  final WidgetMoverFact? mover;
  final WidgetBiggestFact? biggest;
}

class WidgetFeedBuild {
  const WidgetFeedBuild({required this.items, required this.drafts});

  /// En el orden base (§4.2), con ids y textos completos, hasta 8.
  final List<WidgetFeedItem> items;

  /// La pregunta de cada ítem, por id (sin pregunta = no está).
  final Map<String, WidgetQuestionDraft> drafts;
}

class _Candidate {
  _Candidate(this.item, this.draft, this.group, this.seq);

  final WidgetFeedItem item;
  final WidgetQuestionDraft? draft;

  /// Orden dentro de la misma prioridad (§4.2).
  final int group;

  /// Posición en la fuente (la fuente ya viene ordenada).
  final int seq;
}

/// Candidatos del feed, sus segmentos con prioridad y el orden base
/// (docs/specs/home-widget-v2-tech.md §4.1 y §4.2).
abstract final class WidgetFeedBuilder {
  static const maxItems = 8;
  static const insightLife = Duration(hours: 24);

  static WidgetFeedBuild build(WidgetFeedInputs inputs, WidgetTexts t) {
    final now = inputs.now;
    final candidates = <_Candidate>[];
    final selection = inputs.selection;
    var seq = 0;

    if (selection != null) {
      for (final selected in selection.items) {
        switch (selected) {
          case SelectedNews(:final news):
            candidates.add(_news(inputs, t, selected.ticker, news, seq++));
          case SelectedEarnings(:final date):
            candidates.add(_earnings(inputs, t, selected.ticker, date, seq++));
        }
      }
      final teaser = selection.teaser;
      if (teaser != null) candidates.add(_teaser(inputs, t, teaser, seq++));
    }
    for (final insight in inputs.insights) {
      candidates.add(_insight(inputs, t, insight, seq++));
    }
    final mover = inputs.mover;
    if (mover != null) candidates.add(_mover(inputs, t, mover, seq++));
    final biggest = inputs.biggest;
    final hasConcentration = inputs.insights.any(
      (i) => i.kind == WidgetInsightKind.concentration,
    );
    final sameAsMover =
        mover != null &&
        biggest != null &&
        mover.ticker.toUpperCase() == biggest.ticker.toUpperCase();
    if (biggest != null && !hasConcentration && !sameAsMover) {
      candidates.add(_biggest(inputs, t, biggest, seq++));
    }

    candidates.sort((a, b) {
      final byPrio = a.item.prioAt(now).compareTo(b.item.prioAt(now));
      if (byPrio != 0) return byPrio;
      final byGroup = a.group.compareTo(b.group);
      return byGroup != 0 ? byGroup : a.seq.compareTo(b.seq);
    });
    final top = candidates.take(maxItems).toList();
    return WidgetFeedBuild(
      items: [for (final c in top) c.item],
      drafts: {
        for (final c in top)
          if (c.draft != null) c.item.id!: c.draft!,
      },
    );
  }

  // --- Helpers ---

  static String _id(String kind, String subject) =>
      WidgetItemsSelector.itemId('$kind|$subject');

  static WidgetQuestionRef? _ref(WidgetQuestionDraft? d, WidgetTexts t) =>
      d?.toRef(t, hidden: false);

  static DateTime _localMidnight(DateTime local, [int plusDays = 0]) =>
      DateTime(local.year, local.month, local.day + plusDays);

  // --- news ---

  static _Candidate _news(
    WidgetFeedInputs inputs,
    WidgetTexts t,
    String ticker,
    CompanyNewsItem news,
    int seq,
  ) {
    final now = inputs.now;
    final local = now.toLocal();
    final published = news.publishedAt.toLocal();
    final isToday =
        published.year == local.year &&
        published.month == local.month &&
        published.day == local.day;
    WidgetFeedSegment segment(DateTime from, int prio, String shortKey) =>
        WidgetFeedSegment(
          from: from,
          prio: prio,
          short: t.get(shortKey, {'ticker': ticker}),
          title: news.headline,
          meta: t.get('meta_news', {'age': '{age}'}),
        );
    final segments =
        isToday
            ? [
              segment(now, 1, 'short_news_today'),
              segment(_localMidnight(local, 1), 3, 'short_news_yesterday'),
            ]
            : [segment(now, 3, 'short_news_yesterday')];
    final id = WidgetItemsSelector.newsId(ticker, news.url);
    final draft = WidgetQuestionsBuilder.forNews(inputs.tier, ticker);
    return _Candidate(
      WidgetFeedItem(
        id: id,
        kind: WidgetFeedKind.news,
        icon: 'news',
        tag: ticker,
        paid: true,
        publishedAt: news.publishedAt,
        expiresAt: news.publishedAt.add(WidgetItemsSelector.newsWindow),
        segments: segments,
        a11y: t.get('a11y_news', {
          'ticker': ticker,
          'source': news.source,
          'age': '{age}',
          'headline': news.headline,
        }),
        open: WidgetFeedOpen(target: 'news', id: id),
        q: _ref(draft, t),
      ),
      draft,
      isToday ? 1 : 0,
      seq,
    );
  }

  // --- earnings ---

  /// Un segmento por día en que cambia el texto o la prioridad: lejos (3),
  /// a 2 días (1, misma fecha), mañana y hoy.
  static List<WidgetFeedSegment> earningsSegments({
    required String ticker,
    required DateTime date,
    required DateTime now,
    required WidgetTexts texts,
  }) {
    final local = now.toLocal();
    final today = DateTime.utc(local.year, local.month, local.day);
    final day = DateTime.utc(date.year, date.month, date.day);
    final total = day.difference(today).inDays.clamp(0, 365).toInt();
    final weekdays = texts.get('weekdays').split(',');
    final weekday = weekdays[date.weekday % 7];
    final dateLabel = texts.get('date_format', {
      'weekday': weekday,
      'day': '${date.day}',
      'month': texts.months[date.month - 1],
    });
    final segments = <WidgetFeedSegment>[];
    String? lastKey;
    for (var remaining = total; remaining >= 0; remaining--) {
      final suffix =
          remaining == 0 ? 'today' : (remaining == 1 ? 'tomorrow' : 'date');
      final prio = remaining <= 2 ? 1 : 3;
      final key = '$suffix|$prio';
      if (key == lastKey) continue;
      lastKey = key;
      final args = {'ticker': ticker, 'date': dateLabel, 'weekday': weekday};
      segments.add(
        WidgetFeedSegment(
          from:
              remaining == total
                  ? now
                  : DateTime(date.year, date.month, date.day - remaining),
          prio: prio,
          short: texts.get('short_earnings_$suffix', args),
          title: texts.get('earnings_$suffix', args),
          meta: texts.get('meta_earnings'),
        ),
      );
    }
    return segments;
  }

  static _Candidate _earnings(
    WidgetFeedInputs inputs,
    WidgetTexts t,
    String ticker,
    DateTime date,
    int seq,
  ) {
    final segments = earningsSegments(
      ticker: ticker,
      date: date,
      now: inputs.now,
      texts: t,
    );
    final id = WidgetItemsSelector.earningsId(ticker, date);
    final draft = WidgetQuestionsBuilder.forEarnings(inputs.tier, ticker);
    final first = segments.first.prio;
    return _Candidate(
      WidgetFeedItem(
        id: id,
        kind: WidgetFeedKind.earnings,
        icon: 'calendar',
        tag: ticker,
        paid: true,
        expiresAt: DateTime(date.year, date.month, date.day, 23, 59, 59),
        segments: segments,
        a11y: t.get('earnings_date', {
          'ticker': ticker,
          'date': t.get('date_format', {
            'weekday': t.get('weekdays').split(',')[date.weekday % 7],
            'day': '${date.day}',
            'month': t.months[date.month - 1],
          }),
        }),
        open: WidgetFeedOpen(target: 'earnings', id: id),
        q: _ref(draft, t),
      ),
      draft,
      first == 1 ? 0 : 1,
      seq,
    );
  }

  // --- insight ---

  static _Candidate _insight(
    WidgetFeedInputs inputs,
    WidgetTexts t,
    WidgetInsightInput insight,
    int seq,
  ) {
    final title = WidgetInsightCopy.title(insight, t);
    final draft = WidgetQuestionsBuilder.forInsight(
      inputs.tier,
      insight.kind.question,
      ticker: insight.ticker,
      goal: insight.goalLabel,
    );
    return _Candidate(
      WidgetFeedItem(
        id: _id('insight', insight.id),
        kind: WidgetFeedKind.insight,
        icon: 'pie',
        tag: insight.kind.isGoal ? null : insight.ticker,
        expiresAt: inputs.now.add(insightLife),
        segments: [
          WidgetFeedSegment(
            from: inputs.now,
            prio: 2,
            short: title,
            title: title,
            meta: t.get('meta_insight'),
          ),
        ],
        a11y: t.get('a11y_insight', {'title': title}),
        open: const WidgetFeedOpen(target: 'home'),
        q: _ref(draft, t),
      ),
      draft,
      0,
      seq,
    );
  }

  // --- teaser ---

  static String teaserText(
    SelectedTeaser teaser,
    WidgetTexts t,
    WidgetPlatform platform,
  ) {
    final platformKey = platform == WidgetPlatform.ios ? 'ios' : 'android';
    final count = teaser.count;
    if (count == null) return t.get('teaser_news_android_nocount');
    return t.get(
      'teaser_${teaser.kind}_${platformKey}_${count == 1 ? 'one' : 'other'}',
      {'n': '$count'},
    );
  }

  static _Candidate _teaser(
    WidgetFeedInputs inputs,
    WidgetTexts t,
    SelectedTeaser teaser,
    int seq,
  ) {
    final text = teaserText(teaser, t, inputs.platform);
    return _Candidate(
      WidgetFeedItem(
        id: _id('teaser', 'teaser_${teaser.kind}'),
        kind: WidgetFeedKind.teaser,
        icon: 'news',
        expiresAt: inputs.staleAt,
        segments: [
          WidgetFeedSegment(
            from: inputs.now,
            prio: 3,
            short: text,
            title: text,
            meta: t.get('meta_teaser'),
          ),
        ],
        a11y: text,
        open: WidgetFeedOpen(target: 'teaser_${teaser.kind}'),
      ),
      null,
      2,
      seq,
    );
  }

  // --- mover y biggest ---

  static _Candidate _mover(
    WidgetFeedInputs inputs,
    WidgetTexts t,
    WidgetMoverFact mover,
    int seq,
  ) {
    final today = inputs.period == DayMovePeriod.today;
    final text = t.get(today ? 'mover_today' : 'mover_last', {
      'ticker': mover.ticker,
      'pct': AppNumberFormat.percent(mover.pct),
    });
    final draft = WidgetQuestionsBuilder.forMover(
      inputs.tier,
      mover.ticker,
      today: today,
    );
    return _Candidate(
      WidgetFeedItem(
        id: _id('mover', mover.ticker.toUpperCase()),
        kind: WidgetFeedKind.mover,
        icon: 'chart',
        tag: mover.ticker,
        expiresAt: inputs.staleAt,
        segments: [
          WidgetFeedSegment(
            from: inputs.now,
            prio: 3,
            short: text,
            title: text,
            meta: t.get(today ? 'meta_mover_today' : 'meta_mover_last'),
          ),
        ],
        a11y: t.get('a11y_mover', {
          'period': t.get(today ? 'a11y_period_today' : 'a11y_period_last_close'),
          'ticker': mover.ticker,
          'direction': t.get(mover.pct < 0 ? 'a11y_down' : 'a11y_up'),
          'pct': AppNumberFormat.percent(mover.pct.abs(), signed: false),
        }),
        open: const WidgetFeedOpen(target: 'home'),
        q: _ref(draft, t),
      ),
      draft,
      3,
      seq,
    );
  }

  static _Candidate _biggest(
    WidgetFeedInputs inputs,
    WidgetTexts t,
    WidgetBiggestFact biggest,
    int seq,
  ) {
    final text = t.get('biggest', {
      'ticker': biggest.ticker,
      'weight': AppNumberFormat.percent(
        biggest.weightPct,
        decimals: 0,
        signed: false,
      ),
    });
    final draft = WidgetQuestionsBuilder.forBiggest(inputs.tier, biggest.ticker);
    return _Candidate(
      WidgetFeedItem(
        id: _id('biggest', biggest.ticker.toUpperCase()),
        kind: WidgetFeedKind.biggest,
        icon: 'pie',
        tag: biggest.ticker,
        expiresAt: inputs.staleAt,
        segments: [
          WidgetFeedSegment(
            from: inputs.now,
            prio: 3,
            short: text,
            title: text,
            meta: t.get('meta_biggest'),
          ),
        ],
        a11y: text,
        open: const WidgetFeedOpen(target: 'home'),
        q: _ref(draft, t),
      ),
      draft,
      4,
      seq,
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_format.dart';
import 'package:portfolio_assistant/features/daily_brief/view/widgets/daily_brief_feedback.dart';
import 'package:portfolio_assistant/features/news_feed/nav/news_topic_router.dart';
import 'package:portfolio_assistant/features/news_feed/providers/news_holdings_provider.dart';
import 'package:portfolio_assistant/features/news_feed/providers/news_seen_provider.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_actions.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_cards.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_chips.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_image.dart';
import 'package:portfolio_assistant/features/display_currency/view/display_money_scope.dart';
import 'package:portfolio_assistant/features/news_feed/nav/news_feed_router.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_headline_row.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

/// El brief del día: ¿cómo cerró mi cartera?, ¿qué pesó?, ¿con qué noticias
/// coincidió? y ¿qué pasa en el mercado? Una sección sin nada que contar no
/// aparece, y nada se muestra sin medio y link. Los números los pone la app
/// (los mismos de la línea 1D de la Home); el texto es de Porty.
class DailyBriefScreen extends ConsumerStatefulWidget {
  const DailyBriefScreen({super.key, this.day, this.source = 'home'});

  /// `YYYY-MM-DD`; sin valor, el de hoy.
  final String? day;

  /// De dónde se abrió (`push` | `home` | `feed`), para el evento.
  final String source;

  @override
  ConsumerState<DailyBriefScreen> createState() => _DailyBriefScreenState();
}

class _DailyBriefScreenState extends ConsumerState<DailyBriefScreen> {
  bool _opened = false;

  void _logOpened(DailyBrief brief) {
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Abrir el brief de hoy apaga el punto de Noticias.
      ref
          .read(newsSeenProvider.notifier)
          .markSeen(NewsSeenNotifier.markerFor(brief.day));
      ref.read(productEventsProvider).log(ProductEvent.dailyBriefOpened, {
        'source': widget.source,
        'variant': brief.variant.name,
        'courtesy': brief.courtesy,
        'tier': ref.read(dailyBriefTierProvider).name,
      });
    });
  }

  void _tapped(String kind) => ref.read(productEventsProvider).log(
    ProductEvent.dailyBriefItemTapped,
    {'kind': kind},
  );

  void _read(String kind, BriefSource? source) {
    final uri = Uri.tryParse(source?.url ?? '');
    if (uri == null) return;
    _tapped(kind);
    ref.read(dailyBriefUrlLauncherProvider)(uri).catchError((_) => false);
  }

  void _ask(String question, {required String from}) {
    ref.read(productEventsProvider).log(ProductEvent.dailyBriefAskPorty, {
      'from': from,
    });
    GotoAssistant(initialQuestion: question).navigate(context: context);
  }

  void _askAffects(String title, {BriefSource? source, String? ticker}) {
    ref.read(productEventsProvider).log(ProductEvent.newsHowAffectsTapped, {
      'from': 'brief',
    });
    GotoAssistant(
      initialQuestion: 'daily_brief_ask_affects'.tr(
        namedArgs: {'title': title},
      ),
      screen: PortyScreenContext.newsItem(
        PortyNewsItem(
          title: title,
          source: source?.source,
          url: source?.url,
          publishedAt: source?.publishedAt,
          ticker: ticker,
        ),
      ),
    ).navigate(context: context);
  }

  void _compare(String ticker, {required bool held, String? url}) =>
      NewsActions.compare(
        context,
        ref,
        subject: ticker,
        kind: NewsCompareSubject.ticker,
        from: 'brief',
        held: held,
        url: url,
      );

  void _openPaywall() {
    PortyHapticsService.maybeOf(context)?.lockedTap();
    _tapped('teaser');
    SubscriptionPaywallSheet.show(
      context,
      ref,
      reason: PaywallReason.heldNews,
      source: PaywallSource.dailyBrief,
      onUpgraded: () => ref.read(subscriptionProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dailyBriefControllerProvider);
    final today = DailyBriefNumbers.dayKey(DateTime.now());
    final wanted = widget.day ?? today;
    final brief = state.brief?.day == wanted ? state.brief : null;
    if (brief != null) _logOpened(brief);
    final loading = brief == null && state.phase == DailyBriefPhase.loading;
    final colors = context.customColors;
    final date = brief == null ? null : DateTime.tryParse(brief.day);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title:
            brief == null || date == null
                ? null
                : Text(
                  'brief_dateline'.tr(
                    namedArgs: {
                      'day': DailyBriefFormat.weekdayDay(context, date),
                      'min': '${DailyBriefFormat.readMinutes(brief)}',
                    },
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
      ),
      body: LoadingSwitcher(
        loading: loading,
        placeholder:
            (_) => PortyLoader(
              message:
                  state.generating
                      ? 'daily_brief_generating'.tr()
                      : 'loader_one_moment'.tr(),
            ),
        child:
            (_) =>
                brief == null
                    ? _Empty(
                      failed: state.failed,
                      onRetry:
                          () =>
                              ref
                                  .read(dailyBriefControllerProvider.notifier)
                                  .retry(),
                    )
                    : _BriefView(
                      key: ValueKey(brief.day),
                      brief: brief,
                      canCompare: state.status.piece('compare'),
                      feedAvailable: ref.watch(newsFeedAvailableProvider),
                      onRead: _read,
                      onAskAffects: _askAffects,
                      onCompare: _compare,
                      onAskPorty:
                          () => _ask(
                            'daily_brief_ask_question'.tr(),
                            from: 'footer',
                          ),
                      onTeaser: _openPaywall,
                      onOpenTopic: (id) {
                        _tapped('topic');
                        context.pushNamed(NewsTopicRouter.routeName, extra: id);
                      },
                      onSeeAll: () {
                        _tapped('see_all');
                        // Noticias es una pestaña: se va a ella (no se apila).
                        context.goNamed(
                          NewsFeedRouter.routeName,
                          extra: NewsFeedRouter.args(source: 'brief'),
                        );
                      },
                    ),
      ),
    );
  }
}

const _gap = 36.0;

/// Los capítulos del brief, en orden. Uno sin nada que contar no existe.
enum _ChapterKind { mine, watch, market, heads }

class _Chapter {
  const _Chapter(this.kind, this.count);
  final _ChapterKind kind;

  /// Cuántas notas o hechos tiene (para "2 notas"); 0 = no se cuenta.
  final int count;

  String get title => 'brief_chapter_${kind.name}'.tr();

  /// "Lo tuyo · 2 notas" (o solo el título).
  String get heading {
    if (count == 0) return title;
    return (count == 1 ? 'brief_chapter_count_one' : 'brief_chapter_count').tr(
      namedArgs: {'title': title, 'n': '$count'},
    );
  }

  static List<_Chapter> of(DailyBrief brief) {
    final n = brief.numbers;
    final mineNotes =
        {
          for (final l in [...brief.why, ...brief.heldNews])
            if (l.newsId != null && brief.sourceOf(l.newsId) != null) l.newsId,
        }.length;
    return [
      if (n.movers.isNotEmpty || mineNotes > 0)
        _Chapter(_ChapterKind.mine, mineNotes),
      if (brief.watchNews.isNotEmpty)
        _Chapter(_ChapterKind.watch, brief.watchNews.length),
      if (brief.market.isNotEmpty)
        _Chapter(_ChapterKind.market, brief.market.length),
      if (brief.earnings.isNotEmpty ||
          brief.signals.any((s) => s.kind == 'concentration'))
        const _Chapter(_ChapterKind.heads, 0),
    ];
  }
}

/// El brief entero: Porty y el titular arriba, la barra de capítulos, el
/// capítulo actual y, abajo, "Sigue: …" con el aviso de que es un resumen
/// automático. Se pasa de capítulo con la barra de progreso o con "Sigue".
class _BriefView extends ConsumerStatefulWidget {
  const _BriefView({
    super.key,
    required this.brief,
    required this.canCompare,
    required this.feedAvailable,
    required this.onRead,
    required this.onAskAffects,
    required this.onCompare,
    required this.onAskPorty,
    required this.onTeaser,
    required this.onOpenTopic,
    required this.onSeeAll,
  });

  final DailyBrief brief;
  final bool canCompare;
  final bool feedAvailable;
  final void Function(String kind, BriefSource? source) onRead;
  final void Function(String title, {BriefSource? source, String? ticker})
  onAskAffects;
  final void Function(String ticker, {required bool held, String? url})
  onCompare;
  final VoidCallback onAskPorty;
  final VoidCallback onTeaser;
  final ValueChanged<String> onOpenTopic;
  final VoidCallback onSeeAll;

  @override
  ConsumerState<_BriefView> createState() => _BriefViewState();
}

class _BriefViewState extends ConsumerState<_BriefView> {
  final _scroll = ScrollController();
  int _index = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final brief = widget.brief;
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final chapters = _Chapter.of(brief);
    final index = chapters.isEmpty ? 0 : _index.clamp(0, chapters.length - 1);
    final isLast = chapters.isEmpty || index == chapters.length - 1;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final weights = ref.watch(newsHoldingWeightsProvider);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              AppDimens.sp8,
              AppDimens.pageHorizontal,
              AppDimens.sp24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Intro(brief: brief),
                if (chapters.isNotEmpty) ...[
                  const SizedBox(height: AppDimens.sp8),
                  _ProgressBar(chapters: chapters, index: index, onSelect: _go),
                  const SizedBox(height: AppDimens.sp12),
                  _ChapterHeading(
                    number: index + 1,
                    text: chapters[index].heading,
                  ),
                  const SizedBox(height: AppDimens.sp16),
                  AnimatedSwitcher(
                    duration:
                        reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    layoutBuilder:
                        (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          children: [...previous, if (current != null) current],
                        ),
                    child: KeyedSubtree(
                      key: ValueKey(chapters[index].kind),
                      child: _ChapterBody(
                        kind: chapters[index].kind,
                        brief: brief,
                        weights: weights,
                        canCompare: widget.canCompare,
                        onRead: widget.onRead,
                        onAskAffects: widget.onAskAffects,
                        onCompare: widget.onCompare,
                        onOpenTopic: widget.onOpenTopic,
                      ),
                    ),
                  ),
                ],
                if (isLast && brief.teaser != null)
                  _Teaser(onTap: widget.onTeaser),
                if (isLast)
                  _Footer(
                    brief: brief,
                    feedAvailable: widget.feedAvailable,
                    onAskPorty: widget.onAskPorty,
                    onSeeAll: widget.onSeeAll,
                  ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.background),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                AppDimens.sp8,
                AppDimens.pageHorizontal,
                AppDimens.sp12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isLast)
                    _NextBar(
                      number: index + 2,
                      chapter: chapters[index + 1],
                      onTap: () => _go(index + 1),
                    ),
                  const SizedBox(height: AppDimens.sp8),
                  Text(
                    'news_ai_notice'.tr(),
                    textAlign: TextAlign.center,
                    style: tt.labelSmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Porty saluda (con la cara del día), el titular con el % coloreado, lo que
/// más pesó y el monto del cierre.
class _Intro extends StatelessWidget {
  const _Intro({required this.brief});
  final DailyBrief brief;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final n = brief.numbers;
    final asOf = n.asOfDay;
    final money = DisplayMoneyScope.of(context);
    final courtesyText =
        !brief.courtesy
            ? null
            : brief.courtesyNumber != null && brief.courtesyTotal != null
            ? 'daily_brief_courtesy_n'.tr(
              namedArgs: {
                'n': '${brief.courtesyNumber}',
                'total': '${brief.courtesyTotal}',
              },
            )
            : 'daily_brief_courtesy'.tr();
    final headline = 'brief_headline'.tr(namedArgs: {'pct': '\u0001'});
    final parts = headline.split('\u0001');
    final weighed = [
      for (final m in n.movers)
        '**${m.ticker} ${DailyBriefFormat.pct(m.pct)}**',
    ];
    final weighedText =
        weighed.isEmpty
            ? null
            : weighed.length == 1
            ? weighed.first
            : '${weighed.take(weighed.length - 1).join(', ')}'
                ' ${'brief_and'.tr()} ${weighed.last}';
    final secondary = tt.bodyMedium?.copyWith(
      color: colors.textSecondary,
      height: 1.4,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PortySays(
          messageKey: 'brief-intro',
          mood: DailyBriefFormat.moodOf(n.pct),
          message: Text(
            'brief_porty_intro'.tr(),
            style: PortySays.style(context),
          ),
        ),
        if (courtesyText != null) ...[
          const SizedBox(height: AppDimens.sp8),
          Text(courtesyText, style: secondary),
        ],
        const SizedBox(height: AppDimens.sp16),
        Semantics(
          header: true,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: parts.first),
                TextSpan(
                  text: DailyBriefFormat.pct(n.pct),
                  style: TextStyle(
                    color: colors.pnlColor(n.pct),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (parts.length > 1) TextSpan(text: parts.last),
              ],
            ),
            style: tt.headlineMedium?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              height: 1.15,
              color: colors.textPrimary,
            ),
          ),
        ),
        if (weighedText != null) ...[
          const SizedBox(height: AppDimens.sp6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${'brief_weighed'.tr()} '),
                ...DailyBriefFormat.markedSpans(
                  weighedText,
                  TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            style: secondary?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        const SizedBox(height: AppDimens.sp4),
        Text(
          [
            'daily_brief_amount_closed'.tr(
              namedArgs: {'amount': money.signedMoney(n.abs)},
            ),
            if (asOf != null)
              'daily_brief_closing_of'.tr(
                namedArgs: {'date': DailyBriefFormat.day(context, asOf)},
              ),
          ].join(' · '),
          style: tt.bodySmall?.copyWith(
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Una barra por capítulo: llena hasta el actual. Tocar una salta a ese
/// capítulo (la zona táctil es de 44 px; la barra se ve de 4).
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.chapters,
    required this.index,
    required this.onSelect,
  });

  final List<_Chapter> chapters;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Row(
      children: [
        for (var i = 0; i < chapters.length; i++) ...[
          if (i > 0) const SizedBox(width: AppDimens.sp8),
          Expanded(
            child: Semantics(
              button: true,
              selected: i == index,
              label: 'brief_chapter_go'.tr(
                namedArgs: {'n': '${i + 1}', 'title': chapters[i].title},
              ),
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onSelect(i),
                child: SizedBox(
                  height: AppDimens.touchTarget,
                  child: Center(
                    child: AnimatedContainer(
                      duration:
                          reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            i <= index
                                ? colors.textPrimary
                                : colors.textSecondary.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "1 · Lo tuyo · 2 notas": el número en un círculo de tinta.
class _ChapterHeading extends StatelessWidget {
  const _ChapterHeading({required this.number, required this.text});
  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.textPrimary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: tt.labelMedium?.copyWith(
                color: colors.background,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: AppDimens.sp8),
          Expanded(
            child: Text(
              text,
              style: tt.titleSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Sigue: 2 · Mercado y temas": pasa al capítulo siguiente.
class _NextBar extends StatelessWidget {
  const _NextBar({
    required this.number,
    required this.chapter,
    required this.onTap,
  });

  final int number;
  final _Chapter chapter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final label = 'brief_next'.tr(
      namedArgs: {'n': '$number', 'title': chapter.title},
    );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: Ink(
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.sp12,
                vertical: AppDimens.sp8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${'brief_next_label'.tr()} '),
                          TextSpan(
                            text: '$number · ${chapter.title}',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: AppDimens.iconMd,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Las notas de una posición en el brief: la principal con su foto, las
/// otras como viñetas.
class _NoteGroup {
  _NoteGroup(this.ticker, this.watch);
  final String ticker;
  final bool watch;
  final List<BriefLine> lines = [];
}

class _ChapterBody extends StatelessWidget {
  const _ChapterBody({
    required this.kind,
    required this.brief,
    required this.weights,
    required this.canCompare,
    required this.onRead,
    required this.onAskAffects,
    required this.onCompare,
    required this.onOpenTopic,
  });

  final _ChapterKind kind;
  final DailyBrief brief;
  final Map<String, double> weights;
  final bool canCompare;
  final void Function(String kind, BriefSource? source) onRead;
  final void Function(String title, {BriefSource? source, String? ticker})
  onAskAffects;
  final void Function(String ticker, {required bool held, String? url})
  onCompare;
  final ValueChanged<String> onOpenTopic;

  /// Agrupa por ticker, en el orden de lo que más pesó y después el resto.
  List<_NoteGroup> _groups(List<BriefLine> lines, {required bool watch}) {
    final order = [
      if (!watch)
        for (final m in brief.numbers.movers) m.ticker,
    ];
    final byTicker = <String, _NoteGroup>{};
    final seen = <String>{};
    for (final l in lines) {
      final id = l.newsId;
      if (id == null || brief.sourceOf(id) == null || !seen.add(id)) continue;
      byTicker
          .putIfAbsent(l.ticker, () => _NoteGroup(l.ticker, watch))
          .lines
          .add(l);
    }
    final sorted = [
      for (final t in order)
        if (byTicker.containsKey(t)) byTicker.remove(t)!,
      ...byTicker.values,
    ];
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final citations = _Citations();
    final children = <Widget>[];
    Widget gap() => const SizedBox(height: AppDimens.sp24);
    void add(Widget w) {
      if (children.isNotEmpty) children.add(gap());
      children.add(w);
    }

    switch (kind) {
      case _ChapterKind.mine:
        final groups = _groups([...brief.why, ...brief.heldNews], watch: false);
        final withNews = {for (final g in groups) g.ticker};
        for (final m in brief.numbers.movers) {
          if (!withNews.contains(m.ticker)) add(_MoverOnly(mover: m));
        }
        for (final g in groups) {
          add(
            _NoteGroupView(
              group: g,
              brief: brief,
              mover:
                  brief.numbers.movers
                      .where((m) => m.ticker == g.ticker)
                      .firstOrNull,
              fallbackWeight: weights[g.ticker.trim().toUpperCase()],
              citations: citations,
              canCompare: canCompare,
              now: now,
              kind: 'headline',
              onRead: onRead,
              onAskAffects: onAskAffects,
              onCompare: onCompare,
            ),
          );
        }
      case _ChapterKind.watch:
        for (final g in _groups(brief.watchNews, watch: true)) {
          add(
            _NoteGroupView(
              group: g,
              brief: brief,
              fallbackWeight: null,
              citations: citations,
              canCompare: canCompare,
              now: now,
              kind: 'watch',
              onRead: onRead,
              onAskAffects: onAskAffects,
              onCompare: onCompare,
            ),
          );
        }
      case _ChapterKind.market:
        for (final m in brief.market) {
          add(
            _MarketFact(
              fact: m,
              brief: brief,
              citations: citations,
              onRead: onRead,
              onOpenTopic: onOpenTopic,
            ),
          );
        }
      case _ChapterKind.heads:
        for (final e in brief.earnings) {
          add(
            _EarningsRow(
              earning: e,
              onOpen:
                  () => onRead(
                    'earnings',
                    BriefSource(
                      title: e.ticker,
                      source: 'SEC',
                      domain: 'sec.gov',
                      url: e.url ?? '',
                    ),
                  ),
            ),
          );
        }
        for (final s in brief.signals) {
          if (s.kind == 'concentration' &&
              s.ticker != null &&
              s.weightPct != null) {
            add(
              _Prose(
                'daily_brief_signal_concentration'.tr(
                  namedArgs: {
                    'ticker': s.ticker!,
                    'pct': DailyBriefFormat.weight(s.weightPct!),
                  },
                ),
              ),
            );
          }
        }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Numera las citas en orden de aparición: la primera fuente es la 1.
class _Citations {
  final _order = <String>[];
  int indexOf(String key) {
    final i = _order.indexOf(key);
    if (i >= 0) return i + 1;
    _order.add(key);
    return _order.length;
  }
}

/// Una frase de Porty con el dato clave en negrita y, al final, la cita del
/// medio (tocarla abre la nota).
class _CitedText extends StatelessWidget {
  const _CitedText({
    required this.text,
    required this.style,
    required this.source,
    required this.index,
    required this.onTap,
  });

  final String text;
  final TextStyle? style;
  final BriefSource? source;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    return Text.rich(
      TextSpan(
        children: [
          ...DailyBriefFormat.boldFigures(text, bold),
          if (source != null) ...[
            const TextSpan(text: ' '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: CitationChip(
                source: source!.source,
                index: index,
                onTap: onTap,
              ),
            ),
          ],
        ],
      ),
      style: style,
    );
  }
}

class _NoteGroupView extends StatelessWidget {
  const _NoteGroupView({
    required this.group,
    required this.brief,
    required this.citations,
    required this.canCompare,
    required this.now,
    required this.kind,
    required this.onRead,
    required this.onAskAffects,
    required this.onCompare,
    this.mover,
    this.fallbackWeight,
  });

  final _NoteGroup group;
  final DailyBrief brief;
  final BriefMover? mover;
  final double? fallbackWeight;
  final _Citations citations;
  final bool canCompare;
  final DateTime now;
  final String kind;
  final void Function(String kind, BriefSource? source) onRead;
  final void Function(String title, {BriefSource? source, String? ticker})
  onAskAffects;
  final void Function(String ticker, {required bool held, String? url})
  onCompare;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final first = group.lines.first;
    final firstSource = brief.sourceOf(first.newsId);
    final weight = mover?.weightPct ?? fallbackWeight;
    final body = tt.bodyLarge?.copyWith(
      fontSize: 17,
      height: 1.5,
      color: colors.textPrimary,
    );
    final bullet = tt.bodyMedium?.copyWith(
      fontSize: 15,
      height: 1.45,
      color: colors.textPrimary,
    );
    final photo = firstSource?.imageUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (NewsPhoto.usable(photo) && firstSource != null) ...[
          NewsPhoto(
            url: photo,
            height: 150,
            credit: 'news_photo_credit'.tr(
              namedArgs: {'source': firstSource.source},
            ),
          ),
          const SizedBox(height: AppDimens.sp12),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TickerChip(group.ticker),
            if (weight != null && weight.isFinite)
              Text(
                'brief_weight_of_portfolio'.tr(
                  namedArgs: {
                    'pct': AppNumberFormat.percent(weight, signed: false),
                  },
                ),
                style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            if (mover != null && mover!.pct.isFinite)
              Text(
                DailyBriefFormat.pct(mover!.pct),
                style: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.pnlColor(mover!.pct),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.sp8),
        _CitedText(
          text: first.text,
          style: body,
          source: firstSource,
          index: citations.indexOf(first.newsId!),
          onTap: () => onRead(kind, firstSource),
        ),
        if (group.lines.length > 1) ...[
          const SizedBox(height: AppDimens.sp8),
          for (final l in group.lines.skip(1))
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.sp6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 10, left: 4),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _CitedText(
                      text: l.text,
                      style: bullet,
                      source: brief.sourceOf(l.newsId),
                      index: citations.indexOf(l.newsId!),
                      onTap: () => onRead(kind, brief.sourceOf(l.newsId)),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppDimens.sp4),
        Wrap(
          spacing: AppDimens.sp8,
          children: [
            NewsPill(
              filled: true,
              label: 'daily_brief_how_affects'.tr(),
              onTap:
                  () => onAskAffects(
                    firstSource?.title ?? first.text,
                    source: firstSource,
                    ticker: group.ticker,
                  ),
            ),
            if (canCompare)
              NewsPill(
                label: 'news_feed_compare'.tr(),
                onTap:
                    () => onCompare(
                      group.ticker,
                      held: !group.watch,
                      url: firstSource?.url,
                    ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Una posición que movió la cartera y de la que no hay notas: el dato
/// (peso y aporte), sin inventar una explicación.
class _MoverOnly extends StatelessWidget {
  const _MoverOnly({required this.mover});
  final BriefMover mover;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final money = DisplayMoneyScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TickerChip(mover.ticker),
            const Spacer(),
            Text(
              DailyBriefFormat.pct(mover.pct),
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.pnlColor(mover.pct),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.sp4),
        Text(
          'daily_brief_mover_detail'.tr(
            namedArgs: {
              'contribution': money.signedMoney(mover.contributionAbs),
              'weight': DailyBriefFormat.weight(mover.weightPct),
            },
          ),
          style: tt.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Un hecho de mercado (validado por el servidor) con su cita, cómo te toca
/// (si Porty lo conecta con tu cartera) y el acceso al tema.
class _MarketFact extends StatelessWidget {
  const _MarketFact({
    required this.fact,
    required this.brief,
    required this.citations,
    required this.onRead,
    required this.onOpenTopic,
  });

  final BriefMarketLine fact;
  final DailyBrief brief;
  final _Citations citations;
  final void Function(String kind, BriefSource? source) onRead;
  final ValueChanged<String> onOpenTopic;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final id = fact.sourceIds.firstWhere(
      (i) => brief.sourceOf(i) != null,
      orElse: () => '',
    );
    final source = brief.sourceOf(id.isEmpty ? null : id);
    final topic = fact.topicId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CitedText(
          text: fact.text,
          style: tt.bodyLarge?.copyWith(
            fontSize: 17,
            height: 1.5,
            color: colors.textPrimary,
          ),
          source: source,
          index: id.isEmpty ? 0 : citations.indexOf(id),
          onTap: () => onRead('macro', source),
        ),
        if (fact.connection != null) ...[
          const SizedBox(height: AppDimens.sp8),
          WhyChip(fact.connection!),
        ],
        if (topic != null)
          TextButton(
            onPressed: () => onOpenTopic(topic),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppDimens.touchTarget),
              padding: EdgeInsets.zero,
              foregroundColor: colors.accentBlue,
            ),
            child: Text('brief_see_topic'.tr()),
          ),
      ],
    );
  }
}

/// El aviso de plan de Free: dice qué trae el plan siguiente, sin ticker ni
/// cifras de lo que se pierde.
class _Teaser extends StatelessWidget {
  const _Teaser({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: _gap),
      child: Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDimens.sp8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'daily_brief_teaser_premium'.tr(),
                          style: tt.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: AppDimens.sp4),
                        Text(
                          'daily_brief_teaser_cta'.tr(),
                          style: tt.labelLarge?.copyWith(
                            color: colors.accentBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EarningsRow extends StatelessWidget {
  const _EarningsRow({required this.earning, required this.onOpen});
  final BriefEarning earning;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final hasLink = earning.reported && (earning.url ?? '').isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DailyBriefFormat.earnings(context, earning),
            style: tt.bodyLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (!earning.reported)
            Text(
              'daily_brief_estimated'.tr(),
              style: tt.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          if (hasLink)
            TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppDimens.touchTarget),
                padding: EdgeInsets.zero,
                foregroundColor: colors.accentBlue,
              ),
              child: Text('daily_brief_earnings_source'.tr()),
            ),
        ],
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({
    required this.brief,
    required this.feedAvailable,
    required this.onAskPorty,
    required this.onSeeAll,
  });

  final DailyBrief brief;
  final bool feedAvailable;
  final VoidCallback onAskPorty;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: _gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: colors.border),
          const SizedBox(height: AppDimens.sp16),
          Text(
            DailyBriefFormat.asOf(context, brief.asOf),
            style: tt.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.sp16),
          Align(
            alignment: Alignment.centerLeft,
            child: NewsHeadlineActions(
              // "Ver todas las noticias": solo con el feed prendido.
              readLabel: feedAvailable ? 'daily_brief_see_all'.tr() : null,
              onRead: feedAvailable ? onSeeAll : null,
              askLabel: 'daily_brief_ask_porty'.tr(),
              onAsk: onAskPorty,
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          DailyBriefFeedback(
            onAnswer:
                (useful, reason) => ref.read(productEventsProvider).log(
                  ProductEvent.dailyBriefFeedback,
                  {'useful': useful, if (reason != null) 'reason': reason},
                ),
          ),
        ],
      ),
    );
  }
}

class _Prose extends StatelessWidget {
  const _Prose(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppDimens.sp12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: context.customColors.textPrimary,
        height: 1.4,
      ),
    ),
  );
}

/// Sin brief de hoy (o no se pudo armar): Porty lo dice, sin caja vacía.
class _Empty extends StatelessWidget {
  const _Empty({required this.failed, required this.onRetry});
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppDimens.pageHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PortySays(
            messageKey: failed ? 'error' : 'empty',
            mood: failed ? PortyAvatarState.concerned : PortyAvatarState.idle,
            message: Text(
              (failed ? 'daily_brief_error_title' : 'daily_brief_empty_title')
                  .tr(),
              style: PortySays.style(context),
            ),
          ),
          const SizedBox(height: AppDimens.sp12),
          Text(
            (failed ? 'daily_brief_error_body' : 'daily_brief_empty_body').tr(),
            style: tt.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          if (failed) ...[
            const SizedBox(height: AppDimens.sp16),
            NewsHeadlineActions(readLabel: 'retry'.tr(), onRead: onRetry),
          ],
        ],
      ),
    );
  }
}

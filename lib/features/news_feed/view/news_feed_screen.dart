import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
import 'package:portfolio_assistant/features/daily_brief/nav/daily_brief_router.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_format.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
import 'package:portfolio_assistant/features/news_feed/providers/news_holdings_provider.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_cards.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_chips.dart';
import 'package:portfolio_assistant/features/news_feed/nav/news_topic_router.dart';
import 'package:portfolio_assistant/features/news_feed/providers/news_feed_provider.dart';
import 'package:portfolio_assistant/features/news_feed/view/market_today_screen.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_actions.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_article_row.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_states.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_video_sheet.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_videos_section.dart';
import 'package:portfolio_assistant/features/news_preferences/nav/news_preferences_router.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';

enum NewsFeedTab {
  mine,
  topics,
  market,
  videos;

  static NewsFeedTab parse(String? raw) => NewsFeedTab.values.firstWhere(
    (t) => t.name == raw,
    orElse: () => NewsFeedTab.mine,
  );
}

/// Noticias: "Lo tuyo" (cartera y, en Gold, watchlist), "Temas" y "Mercado".
/// Free ve cuántas noticias hay de lo suyo, sin tickers; temas, mercado y
/// videos son iguales en todos los planes.
class NewsFeedScreen extends ConsumerStatefulWidget {
  const NewsFeedScreen({super.key, this.tab = 'mine', this.source = 'home'});

  final String tab;

  /// `brief` | `home` | `push`.
  final String source;

  @override
  ConsumerState<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends ConsumerState<NewsFeedScreen> {
  late NewsFeedTab _tab = NewsFeedTab.parse(widget.tab);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final events = ref.read(productEventsProvider);
      events.log(ProductEvent.newsFeedOpened, {
        'tab': _tab.name,
        'source': widget.source,
      });
      if (_tab == NewsFeedTab.market) {
        events.log(ProductEvent.marketTodayOpened, {'source': 'feed'});
      }
      // Ya cargado antes: se refresca sin borrar lo que se ve.
      if (ref.read(newsFeedProvider).phase != NewsLoadPhase.loading) {
        ref.read(newsFeedProvider.notifier).load();
      }
    });
  }

  void _select(NewsFeedTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab == NewsFeedTab.market) {
      ref.read(productEventsProvider).log(ProductEvent.marketTodayOpened, {
        'source': 'feed',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(newsStatusProvider).valueOrNull;
    final tabs = [
      NewsFeedTab.mine,
      if (status?.piece('topics') ?? true) NewsFeedTab.topics,
      if (status?.piece('market') ?? true) NewsFeedTab.market,
      if (status?.piece('videos') ?? true) NewsFeedTab.videos,
    ];
    final tab = tabs.contains(_tab) ? _tab : NewsFeedTab.mine;
    final canPrefs =
        (status?.piece('topics') ?? true) || (status?.piece('sources') ?? true);
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp8,
            AppDimens.pageHorizontal,
            // La barra flotante de abajo (el body se extiende detrás).
            AppDimens.sp48 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'news_feed_title'.tr(),
                        style: tt.headlineMedium?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (canPrefs)
                    IconButton(
                      tooltip: 'news_feed_prefs'.tr(),
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(AppDimens.touchTarget),
                        backgroundColor: colors.surfaceElevated,
                        foregroundColor: colors.textPrimary,
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      onPressed:
                          () => context.pushNamed(
                            NewsPreferencesRouter.routeName,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.sp8),
              NewsPortyLine(
                messageKey: tab.name,
                text: 'news_porty_${tab.name}'.tr(),
              ),
              const SizedBox(height: AppDimens.sp8),
              _NewsTabs(tabs: tabs, selected: tab, onSelect: _select),
              const SizedBox(height: AppDimens.sp16),
              switch (tab) {
                NewsFeedTab.mine => _MineTab(
                  canCompare: status?.piece('compare') ?? true,
                ),
                NewsFeedTab.topics => const _TopicsTab(),
                NewsFeedTab.market => const MarketTodayBody(),
                NewsFeedTab.videos => const _VideosTab(),
              },
            ],
          ),
        ),
      ),
    );
  }
}

/// Las pestañas: texto con subrayado en la activa (tinta, 2 px), 44 de alto.
class _NewsTabs extends StatelessWidget {
  const _NewsTabs({
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<NewsFeedTab> tabs;
  final NewsFeedTab selected;
  final ValueChanged<NewsFeedTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in tabs)
              Semantics(
                button: true,
                selected: t == selected,
                child: InkWell(
                  onTap: () => onSelect(t),
                  child: AnimatedContainer(
                    duration:
                        reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    height: AppDimens.touchTarget,
                    margin: const EdgeInsets.only(right: AppDimens.sp20),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color:
                              t == selected
                                  ? colors.textPrimary
                                  : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(
                      'news_feed_tab_${t.name}'.tr(),
                      style: tt.titleSmall?.copyWith(
                        fontWeight:
                            t == selected ? FontWeight.w700 : FontWeight.w500,
                        color:
                            t == selected
                                ? colors.textPrimary
                                : colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// El estado de carga del feed, común a "Lo tuyo" y "Temas".
class _FeedBuilder extends ConsumerWidget {
  const _FeedBuilder({required this.builder});

  final Widget Function(BuildContext context, NewsBundle bundle) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(newsFeedProvider);
    final bundle = state.bundle;
    return LoadingSwitcher(
      loading: bundle == null && state.phase == NewsLoadPhase.loading,
      placeholder: (_) => const SizedBox(height: 240, child: PortyLoader()),
      child: (context) {
        if (bundle == null) {
          return NewsMessage(
            messageKey: 'feed_error',
            failed: !state.disabled,
            text: 'news_feed_error'.tr(),
            actionLabel: state.disabled ? null : 'retry'.tr(),
            onAction: () => ref.read(newsFeedProvider.notifier).load(),
          );
        }
        return builder(context, bundle);
      },
    );
  }
}

class _MineTab extends ConsumerWidget {
  const _MineTab({required this.canCompare});
  final bool canCompare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weights = ref.watch(newsHoldingWeightsProvider);
    final dayMoves = ref.watch(newsHoldingDayMovesProvider);
    return _FeedBuilder(
      builder: (context, bundle) {
        if (bundle.isLocked) {
          return _Locked(
            count: bundle.lockedCount!,
            onTap:
                () => NewsActions.openPaywall(
                  context,
                  ref,
                  source: PaywallSource.newsFeed,
                ),
          );
        }
        if (bundle.mine.isEmpty) {
          return NewsMessage(
            messageKey: 'mine_empty',
            text: 'news_feed_empty_mine'.tr(),
          );
        }
        VoidCallback read(NewsArticle a) =>
            () => NewsActions.read(
              ref,
              a.url,
              kind: a.watch ? 'watch' : 'held',
              preferred: a.preferred,
            );
        VoidCallback? compare(NewsArticle a) =>
            !canCompare || a.ticker == null
                ? null
                : () => NewsActions.compare(
                  context,
                  ref,
                  subject: a.ticker!,
                  kind: NewsCompareSubject.ticker,
                  from: 'feed',
                  held: !a.watch,
                  url: a.url,
                );
        final lead = bundle.mine.first;
        final rest = bundle.mine.skip(1).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BriefEntry(),
            NewsLeadCard(
              article: lead,
              why: newsWhyText(lead, weights),
              dayPct:
                  lead.ticker == null || lead.watch
                      ? null
                      : dayMoves[lead.ticker!.trim().toUpperCase()],
              onRead: read(lead),
              onCompare: compare(lead),
              onAsk:
                  () => NewsActions.askAffects(
                    context,
                    ref,
                    title: lead.title,
                    from: 'feed',
                    source: lead.source,
                    url: lead.url,
                    publishedAt: lead.publishedAt,
                    ticker: lead.ticker,
                  ),
            ),
            for (final a in rest) ...[
              const NewsDivider(),
              NewsCompactRow(
                article: a,
                why: newsWhyText(a, weights),
                onRead: read(a),
              ),
            ],
            const NewsDisclaimer(),
          ],
        );
      },
    );
  }
}

/// "Tu brief de hoy · 4 notas de lo tuyo · 3 min": el acceso al brief, solo
/// si ya está armado.
class _BriefEntry extends ConsumerWidget {
  const _BriefEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dailyBriefControllerProvider);
    final brief = state.phase == DailyBriefPhase.ready ? state.brief : null;
    if (brief == null) return const SizedBox.shrink();
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final notes =
        {
          for (final l in [...brief.why, ...brief.heldNews, ...brief.watchNews])
            if (l.newsId != null && brief.sourceOf(l.newsId) != null) l.newsId,
        }.length;
    final minutes = DailyBriefFormat.readMinutes(brief);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp16),
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label:
            '${'daily_brief_home_title'.tr()}. ${_briefSubtitle(brief, notes, minutes)}',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          onTap:
              () => context.pushNamed(
                DailyBriefRouter.routeName,
                extra: DailyBriefRouter.args(day: brief.day, source: 'feed'),
              ),
          child: Ink(
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: AppDimens.sp12,
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: PortyAvatar(
                    size: 36,
                    state: DailyBriefFormat.moodOf(brief.numbers.pct),
                  ),
                ),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'daily_brief_home_title'.tr(),
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        _briefSubtitle(brief, notes, minutes),
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
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
    );
  }

  static String _briefSubtitle(DailyBrief brief, int notes, int minutes) =>
      notes == 0
          ? 'news_brief_entry_numbers'.tr(namedArgs: {'min': '$minutes'})
          : 'news_brief_entry'.tr(
            namedArgs: {'n': '$notes', 'min': '$minutes'},
          );
}

/// El aviso de plan de Free: cuántas posiciones tienen noticias, sin decir
/// cuáles.
class _Locked extends StatelessWidget {
  const _Locked({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Semantics(
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
                        'news_feed_locked'.tr(namedArgs: {'count': '$count'}),
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
    );
  }
}

class _TopicsTab extends ConsumerWidget {
  const _TopicsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _FeedBuilder(
      builder: (context, bundle) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bundle.topics.isEmpty)
              NewsMessage(
                messageKey: 'topics_empty',
                text: 'news_feed_empty_topics'.tr(),
                actionLabel: 'news_feed_prefs'.tr(),
                onAction:
                    () => context.pushNamed(NewsPreferencesRouter.routeName),
              ),
            for (var i = 0; i < bundle.topics.length; i++) ...[
              if (i > 0) const NewsDivider(),
              _TopicTile(digest: bundle.topics[i], bundle: bundle),
            ],
            const NewsDisclaimer(),
          ],
        );
      },
    );
  }
}

/// Videos de canales oficiales de medios (sin reproducción automática).
class _VideosTab extends ConsumerWidget {
  const _VideosTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _FeedBuilder(
      builder: (context, bundle) {
        if (bundle.videos.isEmpty) {
          return NewsMessage(
            messageKey: 'videos_empty',
            text: 'news_videos_empty'.tr(),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < bundle.videos.length; i++) ...[
              if (i > 0) const NewsDivider(),
              NewsVideoTile(
                video: bundle.videos[i],
                onTap: () {
                  NewsActions.videoOpened(ref, bundle.videos[i]);
                  NewsVideoSheet.show(context, bundle.videos[i]);
                },
              ),
            ],
            const NewsDisclaimer(),
          ],
        );
      },
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.digest, required this.bundle});

  final NewsTopicDigest digest;
  final NewsBundle bundle;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final first = digest.lines.firstOrNull;
    final source = first == null ? null : bundle.sourceOf(first.sourceIds);
    return InkWell(
      onTap:
          () => context.pushNamed(
            NewsTopicRouter.routeName,
            extra: digest.topicId,
          ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      digest.label,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (first != null) ...[
                      const SizedBox(height: AppDimens.sp4),
                      Text(
                        first.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                      if (source != null) ...[
                        const SizedBox(height: AppDimens.sp6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: CitationChip(source: source.source),
                        ),
                      ],
                    ] else
                      Text(
                        'news_topic_screen_empty'.tr(),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.sp8),
              Icon(
                Icons.chevron_right_rounded,
                size: AppDimens.iconMd,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

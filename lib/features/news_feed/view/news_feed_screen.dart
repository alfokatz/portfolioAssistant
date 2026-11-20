import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
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
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';

enum NewsFeedTab {
  mine,
  topics,
  market;

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
    ];
    final tab = tabs.contains(_tab) ? _tab : NewsFeedTab.mine;
    final canPrefs =
        (status?.piece('topics') ?? true) || (status?.piece('sources') ?? true);
    return Scaffold(
      appBar: AppBar(
        title: Text('news_feed_title'.tr()),
        actions: [
          if (canPrefs)
            IconButton(
              tooltip: 'news_feed_prefs'.tr(),
              icon: const Icon(Icons.tune_rounded),
              onPressed:
                  () => context.pushNamed(NewsPreferencesRouter.routeName),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp8,
            AppDimens.pageHorizontal,
            AppDimens.sp40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tabs.length > 1)
                SegmentedChoice<NewsFeedTab>(
                  selected: tab,
                  onChanged: _select,
                  options: [
                    for (final t in tabs)
                      (value: t, label: 'news_feed_tab_${t.name}'.tr()),
                  ],
                ),
              const SizedBox(height: AppDimens.sp16),
              switch (tab) {
                NewsFeedTab.mine => _MineTab(
                  canCompare: status?.piece('compare') ?? true,
                ),
                NewsFeedTab.topics => const _TopicsTab(),
                NewsFeedTab.market => const MarketTodayBody(),
              },
            ],
          ),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < bundle.mine.length; i++) ...[
              if (i > 0) const NewsDivider(),
              NewsArticleRow(
                article: bundle.mine[i],
                kind: bundle.mine[i].watch ? 'watch' : 'held',
                from: 'feed',
                onCompare:
                    !canCompare || bundle.mine[i].ticker == null
                        ? null
                        : () => NewsActions.compare(
                          context,
                          ref,
                          subject: bundle.mine[i].ticker!,
                          kind: NewsCompareSubject.ticker,
                          from: 'feed',
                          held: !bundle.mine[i].watch,
                          url: bundle.mine[i].url,
                        ),
              ),
            ],
            const NewsDisclaimer(),
          ],
        );
      },
    );
  }
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
            if (bundle.videos.isNotEmpty) ...[
              newsBlockGap,
              NewsVideosSection(
                videos: bundle.videos,
                onOpen: (video) {
                  NewsActions.videoOpened(ref, video);
                  NewsVideoSheet.show(context, video);
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
                      if (source != null)
                        Text(
                          source.source,
                          style: tt.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
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

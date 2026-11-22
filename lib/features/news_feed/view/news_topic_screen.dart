import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_format.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_cards.dart';
import 'package:portfolio_assistant/features/news_preferences/view/widgets/topic_grid.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_chips.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/surface_card.dart';
import 'package:portfolio_assistant/features/news_feed/providers/news_feed_provider.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_actions.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_article_row.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_states.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_video_sheet.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_videos_section.dart';
import 'package:portfolio_assistant/features/news_preferences/data/news_preferences_repository.dart';
import 'package:portfolio_assistant/features/news_preferences/domain/news_preferences.dart';
import 'package:portfolio_assistant/features/news_preferences/providers/news_preferences_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_headline_row.dart';

/// Un tema: lo que pasó (resumen con medio y link), los titulares de la
/// allowlist que lo nombran y los videos de medios sobre el tema.
class NewsTopicScreen extends ConsumerStatefulWidget {
  const NewsTopicScreen({super.key, required this.topicId});

  final String topicId;

  @override
  ConsumerState<NewsTopicScreen> createState() => _NewsTopicScreenState();
}

class _NewsTopicScreenState extends ConsumerState<NewsTopicScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(newsPreferencesProvider).loaded) {
        ref.read(newsPreferencesProvider.notifier).load();
      }
    });
  }

  Future<void> _toggleFollow(NewsTopic topic, bool followed) async {
    final failure = await ref
        .read(newsPreferencesProvider.notifier)
        .setTopic(topic, followed: followed);
    if (failure == null || !mounted) return;
    ref
        .read(alertProvider.notifier)
        .showError(
          message: switch (failure) {
            TopicLimitReached() => 'news_prefs_topic_limit'.tr(
              namedArgs: {'max': '${NewsPreferencesLimits.topics}'},
            ),
            _ => 'news_prefs_error'.tr(),
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newsTopicProvider(widget.topicId));
    final prefs = ref.watch(newsPreferencesProvider);
    final status = ref.watch(newsStatusProvider).valueOrNull;
    final brief = ref.watch(
      dailyBriefControllerProvider.select((s) => s.brief),
    );
    final bundle = state.bundle;
    final digest =
        bundle?.topics.where((t) => t.topicId == widget.topicId).firstOrNull;
    final topic = prefs.topics.where((t) => t.id == widget.topicId).firstOrNull;
    final title =
        digest?.label ??
        topic?.label(AppLanguage.code) ??
        'news_topic_screen_title'.tr();
    final canFollow = topic != null && (status?.piece('topics') ?? true);
    final followed = topic != null && prefs.isFollowed(topic);
    // "Por qué te toca": la conexión con tu cartera que Porty ya escribió en
    // el brief de hoy para este tema; sin ella, no hay chip (no se inventa).
    final why =
        brief?.market
            .where((m) => m.topicId == widget.topicId)
            .map((m) => m.connection)
            .whereType<String>()
            .firstOrNull;
    return Scaffold(
      appBar: AppBar(),
      body: LoadingSwitcher(
        loading: bundle == null && state.phase == NewsLoadPhase.loading,
        placeholder: (_) => const PortyLoader(),
        child: (context) {
          if (bundle == null) {
            return Padding(
              padding: const EdgeInsets.all(AppDimens.pageHorizontal),
              child: NewsMessage(
                messageKey: 'topic_error',
                failed: !state.disabled,
                text: 'news_topic_screen_error'.tr(),
                actionLabel: state.disabled ? null : 'retry'.tr(),
                onAction:
                    () =>
                        ref
                            .read(newsTopicProvider(widget.topicId).notifier)
                            .load(),
              ),
            );
          }
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                AppDimens.sp4,
                AppDimens.pageHorizontal,
                AppDimens.sp40,
              ),
              child: _Content(
                topicId: widget.topicId,
                title: title,
                bundle: bundle,
                digest: digest,
                canCompare: status?.piece('compare') ?? true,
                why: why,
                canFollow: canFollow,
                followed: followed,
                onToggleFollow:
                    topic == null
                        ? null
                        : () => _toggleFollow(topic, !followed),
                grid: [
                  for (final t in prefs.topics)
                    (
                      id: t.id,
                      label: t.label(AppLanguage.code),
                      followed: prefs.isFollowed(t),
                    ),
                ],
                onGridToggle: (id, value) {
                  final t = prefs.topics.where((t) => t.id == id).firstOrNull;
                  if (t != null) _toggleFollow(t, value);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.topicId,
    required this.title,
    required this.bundle,
    required this.digest,
    required this.canCompare,
    required this.why,
    required this.canFollow,
    required this.followed,
    required this.onToggleFollow,
    required this.grid,
    required this.onGridToggle,
  });

  final String topicId;
  final String title;
  final NewsBundle bundle;
  final NewsTopicDigest? digest;
  final bool canCompare;
  final String? why;
  final bool canFollow;
  final bool followed;
  final VoidCallback? onToggleFollow;
  final List<TopicGridItem> grid;
  final void Function(String id, bool followed) onGridToggle;

  /// Un medio por dominio, con lo que titula sobre el tema (su primera nota).
  List<NewsArticle> get _perOutlet {
    final seen = <String>{};
    return [
      for (final a in bundle.topicNews)
        if (seen.add(a.domain.isEmpty ? a.source : a.domain)) a,
    ].take(4).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final lines = digest?.lines ?? const <NewsDigestLine>[];
    final empty =
        lines.isEmpty && bundle.topicNews.isEmpty && bundle.videos.isEmpty;
    final outlets = _perOutlet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: tt.headlineMedium?.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Wrap(
          spacing: AppDimens.sp8,
          runSpacing: AppDimens.sp4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (why != null) WhyChip(why!),
            if (canFollow)
              NewsPill(
                filled: followed,
                label:
                    (followed
                            ? 'news_topic_screen_following'
                            : 'news_topic_screen_follow')
                        .tr(),
                onTap: onToggleFollow,
              ),
          ],
        ),
        const SizedBox(height: AppDimens.sp8),
        NewsPortyLine(
          messageKey: followed ? 'following' : 'not-following',
          text:
              (followed ? 'news_topic_porty_following' : 'news_topic_porty')
                  .tr(),
        ),
        if (empty && bundle.topicNewsStatus == NewsListStatus.unavailable)
          NewsMessage(
            messageKey: 'topic_unavailable',
            failed: true,
            text: 'news_topic_unavailable'.tr(),
            actionLabel: 'retry'.tr(),
            onAction:
                () => ref.read(newsTopicProvider(topicId).notifier).load(),
          )
        else if (empty)
          NewsMessage(
            messageKey: 'topic_empty',
            text: 'news_topic_screen_empty'.tr(),
          ),
        if (canCompare && !empty)
          Align(
            alignment: Alignment.centerLeft,
            child: NewsHeadlineActions(
              compareLabel: 'news_feed_compare'.tr(),
              onCompare:
                  () => NewsActions.compare(
                    context,
                    ref,
                    subject: title,
                    kind: NewsCompareSubject.topic,
                    from: 'topic',
                    topicId: digest?.topicId ?? topicId,
                  ),
            ),
          ),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: AppDimens.sp16),
          NewsSectionTitle('market_today_why_title'.tr()),
          const SizedBox(height: AppDimens.sp12),
          for (var i = 0; i < lines.length; i++)
            _DigestPoint(
              number: i + 1,
              line: lines[i],
              source: bundle.sourceOf(lines[i].sourceIds),
              onRead: (url) => NewsActions.read(ref, url, kind: 'topic'),
            ),
        ],
        if (outlets.isNotEmpty) ...[
          const SizedBox(height: AppDimens.sp20),
          _MediaBlock(outlets: outlets),
        ],
        if (bundle.topicNews.isNotEmpty) ...[
          newsBlockGap,
          NewsSectionTitle('news_topic_screen_headlines'.tr()),
          for (var i = 0; i < bundle.topicNews.length; i++) ...[
            if (i > 0) const NewsDivider(),
            NewsArticleRow(
              article: bundle.topicNews[i],
              kind: 'topic',
              from: 'topic',
            ),
          ],
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
        if (grid.isNotEmpty) ...[
          newsBlockGap,
          NewsSectionTitle('news_topic_your_topics'.tr()),
          const SizedBox(height: AppDimens.sp12),
          TopicGrid(items: grid, onToggle: onGridToggle),
        ],
        const NewsDisclaimer(),
      ],
    );
  }
}

/// Un punto del resumen: el número en terracota, la frase con el dato en
/// negrita y la cita del medio.
class _DigestPoint extends StatelessWidget {
  const _DigestPoint({
    required this.number,
    required this.line,
    required this.source,
    required this.onRead,
  });

  final int number;
  final NewsDigestLine line;
  final BriefSource? source;
  final ValueChanged<String> onRead;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final src = source;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$number',
              style: tt.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.accentDim,
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  ...DailyBriefFormat.boldFigures(
                    line.text,
                    const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (src != null) ...[
                    const TextSpan(text: ' '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: CitationChip(
                        source: src.source,
                        onTap: () => onRead(src.url),
                      ),
                    ),
                  ],
                ],
              ),
              style: tt.bodyLarge?.copyWith(
                fontSize: 16,
                height: 1.45,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Lo que dijeron los medios": cada medio con lo que titula sobre el tema
/// y si es de los que seguís (medio preferido).
class _MediaBlock extends StatelessWidget {
  const _MediaBlock({required this.outlets});
  final List<NewsArticle> outlets;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'news_topic_media_title'.tr(),
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          for (var i = 0; i < outlets.length; i++) ...[
            if (i > 0) const NewsDivider(),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppDimens.touchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppDimens.sp8),
                child: Row(
                  children: [
                    SourceMark(outlets[i].source, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            outlets[i].source,
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            'news_topic_media_highlights'.tr(
                              namedArgs: {'title': outlets[i].title},
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (outlets[i].preferred)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(left: AppDimens.sp8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  'news_topic_media_following'.tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

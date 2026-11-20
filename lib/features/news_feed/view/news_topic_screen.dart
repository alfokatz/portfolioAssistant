import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_news_sheet.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (canFollow)
            TextButton(
              onPressed: () => _toggleFollow(topic, !followed),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppDimens.touchTarget),
                foregroundColor:
                    followed
                        ? context.customColors.textSecondary
                        : context.customColors.accentBlue,
              ),
              child: Text(
                (followed
                        ? 'news_topic_screen_following'
                        : 'news_topic_screen_follow')
                    .tr(),
              ),
            ),
          const SizedBox(width: AppDimens.sp8),
        ],
      ),
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
                AppDimens.sp8,
                AppDimens.pageHorizontal,
                AppDimens.sp40,
              ),
              child: _Content(
                topicId: widget.topicId,
                title: title,
                bundle: bundle,
                digest: digest,
                canCompare: status?.piece('compare') ?? true,
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
  });

  final String topicId;
  final String title;
  final NewsBundle bundle;
  final NewsTopicDigest? digest;
  final bool canCompare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = digest?.lines ?? const <NewsDigestLine>[];
    final empty =
        lines.isEmpty && bundle.topicNews.isEmpty && bundle.videos.isEmpty;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (empty)
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
                  ),
            ),
          ),
        if (lines.isNotEmpty) ...[
          NewsSectionTitle('market_today_why_title'.tr()),
          for (final line in lines)
            Builder(
              builder: (context) {
                final source = bundle.sourceOf(line.sourceIds);
                final published = source?.publishedAt;
                return NewsHeadlineRow(
                  meta:
                      source == null
                          ? null
                          : [
                            source.source,
                            if (published != null)
                              WidgetNewsSheet.ageLabel(published, now),
                          ].join(' · '),
                  title: line.text,
                  actions: NewsHeadlineActions(
                    readLabel:
                        source == null
                            ? null
                            : 'news_feed_read_on'.tr(
                              namedArgs: {'source': source.source},
                            ),
                    onRead:
                        source == null
                            ? null
                            : () => NewsActions.read(
                              ref,
                              source.url,
                              kind: 'topic',
                            ),
                    askLabel: 'news_feed_how_affects'.tr(),
                    onAsk:
                        () => NewsActions.askAffects(
                          context,
                          ref,
                          title: line.text,
                          from: 'topic',
                        ),
                  ),
                );
              },
            ),
        ],
        if (bundle.topicNews.isNotEmpty) ...[
          if (lines.isNotEmpty) newsBlockGap,
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
        const NewsDisclaimer(),
      ],
    );
  }
}

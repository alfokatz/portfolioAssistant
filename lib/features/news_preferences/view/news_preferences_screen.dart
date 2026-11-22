import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/features/news_feed/providers/news_feed_provider.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_states.dart';
import 'package:portfolio_assistant/features/news_preferences/data/news_preferences_repository.dart';
import 'package:portfolio_assistant/features/news_preferences/domain/news_preferences.dart';
import 'package:portfolio_assistant/features/news_preferences/providers/news_preferences_provider.dart';
import 'package:portfolio_assistant/features/news_preferences/view/widgets/topic_grid.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_picker_sheet.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';

/// Ajustes → Noticias: qué temas seguís y qué medios preferís o silenciás.
/// Cada sección aparece solo si su pieza del interruptor está prendida.
class NewsPreferencesScreen extends ConsumerStatefulWidget {
  const NewsPreferencesScreen({super.key});

  @override
  ConsumerState<NewsPreferencesScreen> createState() =>
      _NewsPreferencesScreenState();
}

class _NewsPreferencesScreenState extends ConsumerState<NewsPreferencesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(newsPreferencesProvider.notifier).load();
    });
  }

  void _toast(NewsPreferencesFailure failure) {
    final message = switch (failure) {
      TopicLimitReached() => 'news_prefs_topic_limit'.tr(
        namedArgs: {'max': '${NewsPreferencesLimits.topics}'},
      ),
      SourceLimitReached() => 'news_prefs_source_limit'.tr(
        namedArgs: {'max': '${NewsPreferencesLimits.sourcesPerList}'},
      ),
      NewsPreferencesUnavailable() => 'news_prefs_error'.tr(),
    };
    ref.read(alertProvider.notifier).showError(message: message);
  }

  Future<void> _toggleTopic(NewsTopic topic, bool followed) async {
    final failure = await ref
        .read(newsPreferencesProvider.notifier)
        .setTopic(topic, followed: followed);
    if (failure != null && mounted) _toast(failure);
  }

  Future<void> _pickSource(NewsSource source) async {
    final current = ref
        .read(newsPreferencesProvider)
        .preferenceOf(source.domain);
    final picked = await showModalBottomSheet<_SourceChoice>(
      context: context,
      builder:
          (ctx) => SettingsPickerSheet(
            title: source.name,
            children: [
              for (final choice in _SourceChoice.values)
                SettingsPickerOption(
                  label: choice.label,
                  isSelected: choice.preference == current,
                  onTap: () => Navigator.of(ctx).pop(choice),
                ),
            ],
          ),
    );
    if (picked == null || picked.preference == current || !mounted) return;
    final failure = await ref
        .read(newsPreferencesProvider.notifier)
        .setSource(source, picked.preference);
    if (failure != null && mounted) _toast(failure);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newsPreferencesProvider);
    final status = ref.watch(newsStatusProvider).valueOrNull;
    final showTopics = status?.piece('topics') ?? true;
    final showSources = status?.piece('sources') ?? true;
    final language = AppLanguage.code;
    return Scaffold(
      appBar: AppBar(title: Text('news_prefs_title'.tr())),
      body: LoadingSwitcher(
        loading: !state.loaded && !state.loadFailed,
        placeholder: (_) => const PortyLoader(),
        child: (context) {
          if (!state.loaded) {
            return Padding(
              padding: const EdgeInsets.all(AppDimens.pageHorizontal),
              child: NewsMessage(
                messageKey: 'prefs_error',
                failed: true,
                text: 'news_prefs_error'.tr(),
                actionLabel: 'retry'.tr(),
                onAction:
                    () => ref.read(newsPreferencesProvider.notifier).load(),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showTopics) ...[
                    _SectionIntro(
                      title: 'news_prefs_topics_title'.tr(),
                      hint: 'news_prefs_topics_hint'.tr(),
                    ),
                    TopicGrid(
                      items: [
                        for (final topic in state.topics)
                          (
                            id: topic.id,
                            label: topic.label(language),
                            followed: state.isFollowed(topic),
                          ),
                      ],
                      onToggle:
                          (id, followed) => _toggleTopic(
                            state.topics.firstWhere((t) => t.id == id),
                            followed,
                          ),
                    ),
                  ],
                  if (showTopics && showSources) newsBlockGap,
                  if (showSources) ...[
                    _SectionIntro(
                      title: 'news_prefs_sources_title'.tr(),
                      hint: 'news_prefs_sources_hint'.tr(),
                    ),
                    for (final source in state.sources)
                      _SourceRow(
                        source: source,
                        preference: state.preferenceOf(source.domain),
                        onTap: () => _pickSource(source),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _SourceChoice {
  none(null),
  prefer(SourcePreference.prefer),
  mute(SourcePreference.mute);

  const _SourceChoice(this.preference);
  final SourcePreference? preference;

  String get label => 'news_prefs_$name'.tr();
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NewsSectionTitle(title),
        const SizedBox(height: AppDimens.sp4),
        Text(
          hint,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.preference,
    required this.onTap,
  });

  final NewsSource source;
  final SourcePreference? preference;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final label = switch (preference) {
      SourcePreference.prefer => 'news_prefs_prefer'.tr(),
      SourcePreference.mute => 'news_prefs_mute'.tr(),
      null => 'news_prefs_none'.tr(),
    };
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.sp8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  source.name,
                  style: tt.bodyLarge?.copyWith(color: colors.textPrimary),
                ),
              ),
              Text(
                label,
                style: tt.bodyMedium?.copyWith(
                  color:
                      preference == SourcePreference.prefer
                          ? colors.accentBlue
                          : colors.textSecondary,
                  fontWeight:
                      preference == null ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppDimens.sp4),
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

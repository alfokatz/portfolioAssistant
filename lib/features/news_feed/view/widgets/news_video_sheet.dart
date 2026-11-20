import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/youtube_iframe_player.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Cómo se arma el reproductor de un video. Los tests lo reemplazan (no hay
/// WebView en `flutter test`).
typedef NewsVideoPlayerBuilder =
    Widget Function(BuildContext context, String videoId, VoidCallback onError);

final newsVideoPlayerBuilderProvider = Provider<NewsVideoPlayerBuilder>(
  (ref) =>
      (context, videoId, onError) => YoutubeIframePlayer(
        videoId: videoId,
        language: AppLanguage.code,
        onError: onError,
      ),
);

/// Hoja con el video de YouTube embebido, el título, el canal ("Video de
/// YouTube · Reuters") y siempre un "Ver en YouTube". Si el reproductor
/// falla (o el id no sirve para embeber), queda solo el enlace.
class NewsVideoSheet extends ConsumerStatefulWidget {
  const NewsVideoSheet({super.key, required this.video});

  final NewsVideo video;

  static Future<void> show(BuildContext context, NewsVideo video) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => NewsVideoSheet(video: video),
      );

  @override
  ConsumerState<NewsVideoSheet> createState() => _NewsVideoSheetState();
}

class _NewsVideoSheetState extends ConsumerState<NewsVideoSheet> {
  late bool _failed = !widget.video.embeddable;

  void _openOnYoutube() {
    final uri = Uri.tryParse(widget.video.url);
    if (uri == null) return;
    ref.read(dailyBriefUrlLauncherProvider)(uri).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final video = widget.video;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          AppDimens.sp8,
          AppDimens.pageHorizontal,
          AppDimens.sp24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_failed)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                child: ref.watch(newsVideoPlayerBuilderProvider)(
                  context,
                  video.videoId,
                  () {
                    if (mounted) setState(() => _failed = true);
                  },
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: AppDimens.sp4),
                child: Text(
                  'news_video_unavailable'.tr(),
                  style: tt.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            const SizedBox(height: AppDimens.sp16),
            Text(
              video.title,
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: AppDimens.sp4),
            Text(
              'news_video_attribution'.tr(
                namedArgs: {'channel': video.channel},
              ),
              style: tt.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppDimens.sp12),
            Align(
              alignment: Alignment.centerLeft,
              child:
                  _failed
                      ? FilledButton(
                        onPressed: _openOnYoutube,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, AppDimens.composerHeight),
                          backgroundColor: colors.textPrimary,
                          foregroundColor: colors.surfaceCard,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppDimens.radiusLg,
                            ),
                          ),
                        ),
                        child: Text('news_video_open'.tr()),
                      )
                      : TextButton(
                        onPressed: _openOnYoutube,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, AppDimens.touchTarget),
                          padding: EdgeInsets.zero,
                          foregroundColor: colors.accentBlue,
                        ),
                        child: Text('news_video_open'.tr()),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// "Videos": canales oficiales de medios. Sin reproducción automática ni
/// contadores. Sin videos, no se dibuja nada (ni el título).
class NewsVideosSection extends StatelessWidget {
  const NewsVideosSection({
    super.key,
    required this.videos,
    required this.onOpen,
  });

  final List<NewsVideo> videos;
  final ValueChanged<NewsVideo> onOpen;

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) return const SizedBox.shrink();
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'news_video_section'.tr(),
            style: tt.titleLarge?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        for (final video in videos)
          NewsVideoTile(video: video, onTap: () => onOpen(video)),
      ],
    );
  }
}

/// Miniatura 16:9 a la izquierda, título y "Video de YouTube · canal".
class NewsVideoTile extends StatelessWidget {
  const NewsVideoTile({super.key, required this.video, required this.onTap});

  final NewsVideo video;
  final VoidCallback onTap;

  static const _thumbWidth = 124.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final attribution = 'news_video_attribution'.tr(
      namedArgs: {'channel': video.channel},
    );
    return Semantics(
      button: true,
      label: '${video.title}. $attribution',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.sp8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _thumbWidth,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: colors.inset),
                        if (video.thumbnail != null)
                          Image.network(
                            video.thumbnail!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        Center(
                          child: Icon(
                            Icons.play_circle_outline_rounded,
                            size: 32,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: AppDimens.sp4),
                    Text(
                      attribution,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

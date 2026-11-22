import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_image.dart';

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

/// Canal y duración/atribución a la izquierda, título y, a la derecha, la
/// miniatura con el play bien visible (sobre una base tinta: sin miniatura,
/// o si no carga, queda un cuadro oscuro con el play, nunca un hueco gris).
class NewsVideoTile extends StatelessWidget {
  const NewsVideoTile({super.key, required this.video, required this.onTap});

  final NewsVideo video;
  final VoidCallback onTap;

  static const thumb = 84.0;

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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attribution,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppDimens.sp6),
                      Text(
                        video.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.sp12),
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                    child: SizedBox(
                      width: thumb,
                      height: thumb,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: colors.inverse),
                          NewsPhoto(
                            url: video.thumbnail,
                            width: thumb,
                            height: thumb,
                            radius: 0,
                          ),
                          Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.onInverse,
                              ),
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  size: 22,
                                  color: colors.inverse,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

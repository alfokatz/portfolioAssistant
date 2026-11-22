import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// La foto de una nota (`image_url`, solo https).
///
/// - Sin URL (o con una que no es https): no dibuja nada, ni un hueco.
/// - Cargando: un bloque sobrio del tono `inset`, del mismo tamaño.
/// - Si la imagen falla: se retira sola (queda el layout sin foto), nunca un
///   recuadro gris vacío ni un ícono de error.
/// - La caché es la de Flutter (`ImageCache`) y se decodifica al tamaño
///   pedido ([cacheWidth]), no a la resolución original.
///
/// Con [width] y [height] es una miniatura; con [height] y sin [width], ocupa
/// todo el ancho (la nota grande) y puede llevar [credit] ("Imagen de la nota de Reuters")
/// sobre la imagen.
class NewsPhoto extends StatefulWidget {
  const NewsPhoto({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.credit,
    this.radius = AppDimens.radiusLg,
    this.onUnavailable,
  });

  final String? url;
  final double? width;
  final double? height;

  /// "Imagen de la nota de Reuters", en un chip abajo a la izquierda (solo la grande).
  final String? credit;
  final double radius;

  /// Se llama una vez si la imagen falla (para que el padre saque lo que
  /// armó alrededor).
  final VoidCallback? onUnavailable;

  /// Solo tests y capturas: cambia cómo se obtiene la imagen (sin red).
  @visibleForTesting
  static ImageProvider Function(String url)? debugProvider;

  /// ¿Esta URL se puede mostrar? (https con host).
  static bool usable(String? url) {
    if (url == null) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  @override
  State<NewsPhoto> createState() => _NewsPhotoState();
}

class _NewsPhotoState extends State<NewsPhoto> {
  bool _failed = false;

  @override
  void didUpdateWidget(covariant NewsPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _failed = false;
  }

  void _fail() {
    if (_failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onUnavailable?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    if (_failed || !NewsPhoto.usable(url)) return const SizedBox.shrink();
    final colors = context.customColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final tt = Theme.of(context).textTheme;

    Widget image(double? maxWidth) {
      final provider =
          NewsPhoto.debugProvider?.call(url!) ?? NetworkImage(url!);
      final target = widget.width ?? maxWidth;
      return Image(
        image:
            target != null && target.isFinite
                ? ResizeImage(
                  provider,
                  width: (target * dpr).round(),
                  policy: ResizeImagePolicy.fit,
                )
                : provider,
        fit: BoxFit.cover,
        width: widget.width ?? double.infinity,
        height: widget.height,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, sync) {
          if (reduceMotion || sync) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: child,
          );
        },
        errorBuilder: (_, _, _) {
          _fail();
          return const SizedBox.shrink();
        },
      );
    }

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: LayoutBuilder(
            builder:
                (context, box) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: colors.inset),
                    image(box.maxWidth),
                    if (widget.credit != null)
                      Positioned(
                        left: AppDimens.sp8,
                        bottom: AppDimens.sp8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.inverse.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(
                              AppDimens.radiusSm,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimens.sp8,
                              vertical: 3,
                            ),
                            child: Text(
                              widget.credit!,
                              style: tt.labelSmall?.copyWith(
                                color: colors.onInverse,
                                fontWeight: FontWeight.w500,
                              ),
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

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Una noticia como fila editorial: la línea chica de arriba (ticker ·
/// medio · hace cuánto), el titular y, si se pide, las acciones debajo.
/// Sin card ni borde: los divisores los pone quien la lista.
///
/// La usan la hoja de novedades del widget, el brief y el feed.
class NewsHeadlineRow extends StatelessWidget {
  const NewsHeadlineRow({
    super.key,
    required this.title,
    this.meta,
    this.detail,
    this.actions,
  });

  /// "AAPL · Reuters · hace 25 min". Vacío o `null`: no se dibuja.
  final String? meta;

  /// El titular (o la línea de Porty que lo resume).
  final String title;

  /// Una línea más chica debajo del titular (la conexión con tu cartera).
  final String? detail;

  /// Los botones de la fila ([NewsHeadlineActions]).
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final small = meta ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (small.isNotEmpty)
            Text(
              small,
              style: tt.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          Text(
            title,
            style: tt.bodyLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: AppDimens.sp4),
            Text(
              detail!,
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          if (actions != null) ...[
            const SizedBox(height: AppDimens.sp12),
            actions!,
          ],
        ],
      ),
    );
  }
}

/// Los botones de una [NewsHeadlineRow]: "Leer en (medio)" (contorno) y la
/// pregunta a Porty (acento, sin relleno). Cualquiera puede faltar.
class NewsHeadlineActions extends StatelessWidget {
  const NewsHeadlineActions({
    super.key,
    this.readLabel,
    this.onRead,
    this.askLabel,
    this.onAsk,
  });

  final String? readLabel;
  final VoidCallback? onRead;
  final String? askLabel;
  final VoidCallback? onAsk;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Wrap(
      spacing: AppDimens.sp8,
      runSpacing: AppDimens.sp8,
      children: [
        if (readLabel != null)
          OutlinedButton(
            onPressed: onRead,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppDimens.touchTarget),
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              ),
            ),
            child: Text(readLabel!),
          ),
        if (askLabel != null)
          TextButton(
            onPressed: onAsk,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppDimens.touchTarget),
              foregroundColor: colors.accentBlue,
            ),
            child: Text(askLabel!),
          ),
      ],
    );
  }
}

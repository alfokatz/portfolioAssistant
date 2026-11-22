import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// El ticker de una noticia: relleno terracota con tinta (la marca de Porty
/// sobre una superficie oscura o clara). Texto `inverse` (oscuro en las dos
/// luces) para pasar AA sobre el acento.
class TickerChip extends StatelessWidget {
  const TickerChip(this.ticker, {super.key});
  final String ticker;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentWarm,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          ticker,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.inverse,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// El tema de una noticia, en contorno (no es de tu cartera: es contexto).
class TopicChip extends StatelessWidget {
  const TopicChip(this.label, {super.key, this.onInverse = false});
  final String label;

  /// Dibujado sobre la superficie oscura de "Hoy en tu cartera".
  final bool onInverse;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final fg = onInverse ? colors.onInverse : colors.textPrimary;
    final line = onInverse ? colors.onInverseMuted : colors.border;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        border: Border.all(color: line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// "Tenés NVDA · 18 % de tu cartera": por qué esta nota es tuya. Tinte
/// `chip` con tinta (en oscuro, un escalón de grafito).
class WhyChip extends StatelessWidget {
  const WhyChip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chip,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// La variación del día de un ticker: "+3,4 % hoy", verde o rojo.
class DayMoveChip extends StatelessWidget {
  const DayMoveChip({super.key, required this.percent, required this.suffix});
  final double percent;

  /// "hoy" (traducido por quien lo usa).
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final positive = percent >= 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: positive ? colors.profitContainer : colors.lossContainer,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '${AppNumberFormat.percent(percent)} $suffix',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.pnlColor(percent),
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// El medio como un círculo con su inicial (no se bajan logos: sería una
/// foto más sin permiso ni garantía de que cargue).
class SourceMark extends StatelessWidget {
  const SourceMark(this.name, {super.key, this.size = 20});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final initial = name.trim().isEmpty ? '·' : name.trim()[0].toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surfaceElevated,
          border: Border.all(color: colors.border),
        ),
        child: Text(
          initial,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: size * 0.45,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// La cita de una frase: "Reuters 1". Tocarla abre la nota en el medio.
/// Es chica porque va dentro del texto; el botón "Leer en …" de la nota
/// es el objetivo táctil grande.
class CitationChip extends StatelessWidget {
  const CitationChip({super.key, required this.source, this.index, this.onTap});

  final String source;
  final int? index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final label = index == null ? source : '$source $index';
    return Semantics(
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: source),
                  if (index != null)
                    TextSpan(
                      text: ' $index',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
              style: tt.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

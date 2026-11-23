import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_news_sheet.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_chips.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_image.dart';

/// Por qué una noticia es tuya: "Tenés NVDA · 18 % de tu cartera" (con el
/// peso real de la posición), "Tenés NVDA" si no se conoce el peso o "Lo
/// seguís: NVDA" si viene de la watchlist (Gold). Sin ticker, `null`.
String? newsWhyText(NewsArticle article, Map<String, double> weights) {
  final ticker = article.ticker;
  if (ticker == null) return null;
  if (article.watch) return 'news_why_watch'.tr(namedArgs: {'ticker': ticker});
  final weight = weights[ticker.trim().toUpperCase()];
  if (weight == null || !weight.isFinite) {
    return 'news_why_held'.tr(namedArgs: {'ticker': ticker});
  }
  return 'news_why_held_pct'.tr(
    namedArgs: {
      'ticker': ticker,
      'pct': AppNumberFormat.percent(weight, signed: false),
    },
  );
}

/// "Leer en Reuters"; en un comunicado de la SEC, "Leer en la SEC".
String newsReadLabel(NewsArticle a) =>
    a.isFiling
        ? 'news_feed_read_sec'.tr()
        : 'news_feed_read_on'.tr(namedArgs: {'source': a.source});

/// "Comunicado oficial · 8-K": distingue una nota de la SEC de la prensa.
/// Sobrio: tinte `chip`, ícono de documento y tinta, sin color nuevo.
class FilingChip extends StatelessWidget {
  const FilingChip({super.key, this.form});
  final String? form;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final label =
        form == null
            ? 'news_filing_chip'.tr()
            : 'news_filing_chip_form'.tr(namedArgs: {'form': form!});
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chip,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.description_outlined,
                size: 14,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: AppDimens.sp4),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La línea de Porty de la pestaña Noticias: su cara chica y una frase
/// corta que cambia con la pestaña (con fundido; sin movimiento si el
/// sistema lo pide).
class NewsPortyLine extends StatelessWidget {
  const NewsPortyLine({
    super.key,
    required this.messageKey,
    required this.text,
    this.mood = PortyAvatarState.idle,
  });

  final Object messageKey;
  final String text;
  final PortyAvatarState mood;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ExcludeSemantics(
          child: PortyAvatar(size: 32, state: mood, animated: true),
        ),
        const SizedBox(width: AppDimens.sp12),
        Expanded(
          child: AnimatedSwitcher(
            duration:
                reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            layoutBuilder:
                (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
            child: Semantics(
              key: ValueKey(messageKey),
              liveRegion: true,
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Un botón en píldora (36 px a la vista, 44 de zona táctil): relleno tinta
/// o de contorno.
class NewsPill extends StatelessWidget {
  const NewsPill({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: AppDimens.touchTarget,
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: filled ? colors.textPrimary : colors.surfaceCard,
                shape: StadiumBorder(
                  side:
                      filled
                          ? BorderSide.none
                          : BorderSide(color: colors.border),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Text(
                  label,
                  style: tt.labelLarge?.copyWith(
                    color: filled ? colors.surfaceCard : colors.textPrimary,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _meta(NewsArticle a) {
  final published = a.publishedAt;
  return published == null
      ? ''
      : '· ${WidgetNewsSheet.ageLabel(published, DateTime.now())}';
}

/// La nota principal: foto grande (si hay), el medio con su inicial, el
/// titular grande, por qué es tuya y las dos preguntas a Porty. Tocar la
/// foto o el titular abre la nota en el medio.
class NewsLeadCard extends StatelessWidget {
  const NewsLeadCard({
    super.key,
    required this.article,
    required this.onRead,
    required this.onAsk,
    this.why,
    this.dayPct,
    this.onCompare,
  });

  final NewsArticle article;
  final VoidCallback onRead;
  final VoidCallback onAsk;

  /// [newsWhyText].
  final String? why;

  /// Variación del día del ticker (de lo que movió la cartera), si se sabe.
  final double? dayPct;
  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final age = _meta(article);
    final pct = dayPct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: [newsReadLabel(article), article.title].join('. '),
          excludeSemantics: true,
          child: InkWell(
            onTap: onRead,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!article.isFiling &&
                    NewsPhoto.usable(article.imageUrl)) ...[
                  NewsPhoto(
                    url: article.imageUrl,
                    height: 176,
                    credit: 'news_photo_credit'.tr(
                      namedArgs: {'source': article.source},
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp12),
                ],
                Row(
                  children: [
                    SourceMark(article.source),
                    const SizedBox(width: AppDimens.sp8),
                    Flexible(
                      child: Text(
                        article.source,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (age.isNotEmpty) ...[
                      const SizedBox(width: AppDimens.sp4),
                      Text(
                        age,
                        style: tt.labelLarge?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppDimens.sp8),
                Text(
                  article.title,
                  style: tt.titleLarge?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    height: 1.25,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (article.isFiling) ...[
          const SizedBox(height: AppDimens.sp12),
          FilingChip(form: article.filingForm),
        ],
        if (why != null || (pct != null && pct.isFinite)) ...[
          const SizedBox(height: AppDimens.sp12),
          Wrap(
            spacing: AppDimens.sp8,
            runSpacing: AppDimens.sp8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (why != null) WhyChip(why!),
              if (pct != null && pct.isFinite)
                DayMoveChip(percent: pct, suffix: 'news_today'.tr()),
            ],
          ),
        ],
        if (article.preferred) ...[
          const SizedBox(height: AppDimens.sp8),
          Text(
            'news_feed_preferred'.tr(),
            style: tt.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
        const SizedBox(height: AppDimens.sp4),
        Wrap(
          spacing: AppDimens.sp8,
          children: [
            NewsPill(
              label: 'news_feed_how_affects'.tr(),
              onTap: onAsk,
              filled: true,
            ),
            if (onCompare != null)
              NewsPill(label: 'news_feed_compare'.tr(), onTap: onCompare),
          ],
        ),
      ],
    );
  }
}

/// El resto de las notas: medio y hora, titular, por qué es tuya y, a la
/// derecha, la miniatura (sin foto no hay hueco: el texto toma todo el
/// ancho).
class NewsCompactRow extends StatelessWidget {
  const NewsCompactRow({
    super.key,
    required this.article,
    required this.onRead,
    this.why,
  });

  final NewsArticle article;
  final VoidCallback onRead;
  final String? why;

  static const thumb = 84.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final age = _meta(article);
    return Semantics(
      button: true,
      label: [newsReadLabel(article), article.title].join('. '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onRead,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
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
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: article.source,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            if (age.isNotEmpty) TextSpan(text: ' $age'),
                          ],
                        ),
                        style: tt.labelLarge?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppDimens.sp6),
                      Text(
                        article.title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (article.isFiling || why != null) ...[
                        const SizedBox(height: AppDimens.sp6),
                        Wrap(
                          spacing: AppDimens.sp8,
                          runSpacing: AppDimens.sp6,
                          children: [
                            if (article.isFiling)
                              FilingChip(form: article.filingForm),
                            if (why != null) WhyChip(why!),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!article.isFiling &&
                    NewsPhoto.usable(article.imageUrl)) ...[
                  const SizedBox(width: AppDimens.sp12),
                  NewsPhoto(
                    url: article.imageUrl,
                    width: thumb,
                    height: thumb,
                    radius: AppDimens.radiusMd,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

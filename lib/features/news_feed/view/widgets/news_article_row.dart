import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_news_sheet.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_actions.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_headline_row.dart';

/// Una noticia del feed o de un tema como fila editorial: "AAPL · Reuters ·
/// hace 3 h", el titular y las acciones (leer, ¿cómo me afecta?, qué dice
/// cada medio). Con [onCompare] en `null` no se ofrece comparar.
class NewsArticleRow extends ConsumerWidget {
  const NewsArticleRow({
    super.key,
    required this.article,
    required this.kind,
    required this.from,
    this.onCompare,
  });

  final NewsArticle article;

  /// `held` | `watch` | `topic` (prop `kind` de `news_item_opened`).
  final String kind;

  /// `feed` | `topic` (prop `from` de `news_how_affects_tapped`).
  final String from;
  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final published = article.publishedAt;
    final meta = [
      if (article.ticker != null) article.ticker!,
      article.source,
      if (published != null)
        WidgetNewsSheet.ageLabel(published, DateTime.now()),
    ].join(' · ');
    return NewsHeadlineRow(
      meta: meta,
      title: article.title,
      detail: article.preferred ? 'news_feed_preferred'.tr() : null,
      actions: NewsHeadlineActions(
        readLabel: 'news_feed_read_on'.tr(
          namedArgs: {'source': article.source},
        ),
        onRead:
            () => NewsActions.read(
              ref,
              article.url,
              kind: kind,
              preferred: article.preferred,
            ),
        askLabel: 'news_feed_how_affects'.tr(),
        onAsk:
            () => NewsActions.askAffects(
              context,
              ref,
              title: article.title,
              from: from,
              source: article.source,
              url: article.url,
              publishedAt: article.publishedAt,
              ticker: article.ticker,
            ),
        compareLabel: onCompare == null ? null : 'news_feed_compare'.tr(),
        onCompare: onCompare,
      ),
    );
  }
}

/// Un divisor alineado al texto entre filas editoriales.
class NewsDivider extends StatelessWidget {
  const NewsDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: context.customColors.border);
}

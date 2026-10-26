import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';

/// La card genérica (`QaInfoList`): para lo que no tiene card propia (las
/// alertas, la cuenta, los ajustes…). El modelo pone un título y filas
/// (título, detalle, valor); los números que escribe tienen que estar en
/// los resultados de las tools del turno (lo controla
/// `AssistantAnswerReview`), así una card genérica tampoco inventa cifras.
abstract final class InfoListWidgets {
  static const icons = <String, IconData>{
    'list': Icons.list_alt_rounded,
    'alert': Icons.notifications_active_outlined,
    'account': Icons.person_outline_rounded,
    'settings': Icons.tune_rounded,
    'goal': Icons.flag_outlined,
  };

  static const tones = {'positive', 'negative', 'neutral'};

  static Widget qaInfoList(CatalogItemContext ctx) {
    final data = ctx.data as JsonMap;
    final rows = [
      for (final r in (data['rows'] as List? ?? const []))
        if (r is Map && '${r['title'] ?? ''}'.trim().isNotEmpty) r,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final title = '${data['title'] ?? ''}'.trim();
    final footnote = '${data['footnote'] ?? ''}'.trim();
    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaCardTitle(
            title: title.isEmpty ? 'Lo que encontré' : title,
            icon: icons[data['icon']] ?? Icons.list_alt_rounded,
          ),
          const SizedBox(height: QaSpace.sectionGap),
          for (final (i, r) in rows.take(8).indexed) ...[
            if (i > 0) const SizedBox(height: QaSpace.rowGap),
            _InfoRow(row: r),
          ],
          if (footnote.isNotEmpty) ...[
            const SizedBox(height: QaSpace.sectionGap),
            Text(footnote, style: QaText.caption),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.row});

  final Map<dynamic, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final title = '${row['title']}'.trim();
    final detail = '${row['detail'] ?? ''}'.trim();
    final value = '${row['value'] ?? ''}'.trim();
    final ticker = '${row['ticker'] ?? ''}'.trim().toUpperCase();
    final question = '${row['question'] ?? ''}'.trim();
    final tone = row['tone'];
    final valueColor = switch (tone) {
      'positive' => QaColors.profit,
      'negative' => QaColors.loss,
      _ => QaColors.textPrimary,
    };
    final content = Row(
      children: [
        if (ticker.isNotEmpty)
          QaTickerAvatar(ticker: ticker, size: 32)
        else
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: switch (tone) {
                'positive' => QaColors.profit,
                'negative' => QaColors.loss,
                _ => QaColors.accentBlue,
              },
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: QaText.bodyStrong),
              if (detail.isNotEmpty) Text(detail, style: QaText.label),
            ],
          ),
        ),
        if (value.isNotEmpty) ...[
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: QaText.valueSm.copyWith(color: valueColor),
            ),
          ),
        ],
        if (question.isNotEmpty) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: QaColors.textSecondary,
          ),
        ],
      ],
    );
    return question.isEmpty
        ? content
        : QaTappable(question: question, child: content);
  }
}

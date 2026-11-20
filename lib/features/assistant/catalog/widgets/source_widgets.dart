import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/data/web/source_comparison_card_data.dart';
import 'package:portfolio_assistant/features/assistant/utils/answer_sources.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Cards de la comparación de medios (`compare_sources`).
abstract final class SourceWidgets {
  /// `QaSourceComparison`: sin props. La dibuja la app desde el resultado de
  /// `compare_sources` del turno; sin él no se dibuja nada (el chequeo de
  /// grounding ya rechaza esa respuesta).
  static Widget qaSourceComparison(CatalogItemContext ctx) => Builder(
    builder:
        (context) => ValueListenableBuilder<TurnEvidence>(
          valueListenable: QaEvidenceScope.listenableOf(context, ctx.surfaceId),
          builder: (context, evidence, _) {
            final data = SourceComparisonCardData.from(evidence);
            return data == null
                ? const SizedBox.shrink()
                : QaCardShell(
                  child: _ComparisonBody(data: data, ctx: ctx),
                );
          },
        ),
  );
}

class _ComparisonBody extends StatelessWidget {
  const _ComparisonBody({required this.data, required this.ctx});

  final SourceComparisonCardData data;
  final CatalogItemContext ctx;

  /// El orden de las filas y la clave de su título.
  static const _kinds = [
    ('agree', 'qa_src_compare_agree'),
    ('differ', 'qa_src_compare_differ'),
    ('only', 'qa_src_compare_only'),
  ];

  @override
  Widget build(BuildContext context) {
    final sections = [
      for (final (kind, titleKey) in _kinds)
        if (data.of(kind).isNotEmpty) (titleKey, data.of(kind)),
    ];
    final ticker = data.ticker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaCardTitle(
          title: 'qa_src_compare_title'.tr(),
          subtitle: data.subject.isEmpty ? null : data.subject,
          icon: Icons.compare_arrows_rounded,
        ),
        for (final (i, (titleKey, points)) in sections.indexed)
          QaSection(
            title: titleKey.tr(),
            first: i == 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (j, point) in points.indexed) ...[
                  if (j > 0) const SizedBox(height: QaSpace.rowGap),
                  _PointRow(point: point),
                ],
              ],
            ),
          ),
        if (data.outlets.isNotEmpty) ...[
          const SizedBox(height: QaSpace.gap),
          Text(
            'qa_src_compare_outlets'.tr(
              namedArgs: {'outlets': data.outlets.join(', ')},
            ),
            style: QaText.label,
          ),
        ],
        if (ticker != null)
          QaFollowUpBar(
            surfaceId: ctx.surfaceId,
            items: QaTickerFollowUps.of(
              ticker,
              exclude: const {
                QaTickerFollowUps.compare,
                QaTickerFollowUps.earnings,
                QaTickerFollowUps.fundamentals,
              },
            ),
          ),
      ],
    );
  }
}

/// Una fila: lo que dice (o en lo que coinciden) y, debajo, cada medio con su
/// link tocable.
class _PointRow extends StatelessWidget {
  const _PointRow({required this.point});

  final ComparisonPoint point;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(point.text, style: QaText.body),
        const SizedBox(height: 2),
        Wrap(
          spacing: 12,
          children: [for (final s in point.sources) _OutletLink(source: s)],
        ),
      ],
    );
  }
}

class _OutletLink extends StatelessWidget {
  const _OutletLink({required this.source});

  final ComparisonSource source;

  @override
  Widget build(BuildContext context) {
    final outlet =
        source.outlet.isNotEmpty
            ? source.outlet
            : (Uri.tryParse(source.url)?.host ?? '');
    return Semantics(
      link: true,
      label: 'qa_src_semantics'.tr(
        namedArgs: {
          'source': outlet,
          'title': source.title.isEmpty ? outlet : source.title,
        },
      ),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _openExternal(source.url),
        borderRadius: BorderRadius.circular(QaSpace.chipRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                outlet,
                style: QaText.label.copyWith(
                  color: QaColors.accentBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.open_in_new_rounded,
                size: 14,
                color: QaColors.accentBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nunca lanza: un link roto no puede tumbar la respuesta.
Future<void> _openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
    return;
  }
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// De dónde salió lo que dice la respuesta, con links (ver [AnswerSources]):
/// las citas de la búsqueda web — OpenAI exige que se vean y se puedan
/// tocar — y las presentaciones a la SEC. Va en el pie del mensaje.
///
/// Sin caja (como las filas editoriales del DESIGN.md): un rótulo y filas
/// tocables de 44 px con el medio, el título y el ícono de link externo.
class QaSourceList extends StatefulWidget {
  const QaSourceList({super.key, required this.sources});

  final List<MessageSource> sources;

  static const collapsedCount = 4;

  @override
  State<QaSourceList> createState() => _QaSourceListState();
}

class _QaSourceListState extends State<QaSourceList> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.sources;
    final visible =
        _expanded ? all : all.take(QaSourceList.collapsedCount).toList();
    final hidden = all.length - visible.length;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('qa_src_sources'.tr(), style: QaText.eyebrow),
          const SizedBox(height: 2),
          for (final s in visible) _SourceRow(link: s),
          if (hidden > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = true),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  foregroundColor: QaColors.accentBlue,
                ),
                child: Text(
                  'qa_src_more'.tr(namedArgs: {'count': '$hidden'}),
                  style: QaText.label.copyWith(color: QaColors.accentBlue),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.link});

  final MessageSource link;

  @override
  Widget build(BuildContext context) {
    final source = link.source.isNotEmpty ? link.source : link.host;
    final title = link.title.isNotEmpty ? link.title : link.host;
    return Semantics(
      link: true,
      label: 'qa_src_semantics'.tr(
        namedArgs: {'source': source, 'title': title},
      ),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _openExternal(link.url),
        borderRadius: BorderRadius.circular(QaSpace.chipRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: source,
                          style: QaText.label.copyWith(
                            color: QaColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (title != source)
                          TextSpan(text: '  $title', style: QaText.label),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: QaColors.accentBlue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

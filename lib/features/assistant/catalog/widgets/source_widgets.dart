import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/utils/answer_sources.dart';
import 'package:url_launcher/url_launcher.dart';

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
          Text('FUENTES', style: QaText.eyebrow),
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
                  'Ver $hidden más',
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
      label: '$source: $title',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _open(link.url),
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

  /// Nunca lanza: un link roto no puede tumbar la respuesta.
  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

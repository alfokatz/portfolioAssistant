import 'package:flutter/material.dart';

/// Cómo se lee el texto de Porty (`QaAnswerText`): párrafos separados por un
/// renglón en blanco y viñetas ("• " o "- ") con sangría colgante.
abstract final class AnswerTextFormat {
  /// Desde este largo, un bloque sin saltos de línea se parte en párrafos.
  static const longBlock = 260;

  /// Oraciones por párrafo al partir un bloque largo.
  static const sentencesPerParagraph = 2;

  /// Red de seguridad para una respuesta larga escrita de corrido (el prompt
  /// pide párrafos o viñetas, pero el modelo no siempre cumple): la parte en
  /// párrafos de [sentencesPerParagraph] oraciones. Un texto que ya trae
  /// saltos de línea, o uno corto, queda igual.
  static String normalize(String text) {
    // Sin markdown (el prompt lo pide; si igual llega, no se ven asteriscos).
    final trimmed = text.replaceAll('**', '').trim();
    if (trimmed.length < longBlock || trimmed.contains('\n')) return trimmed;
    final sentences = splitSentences(trimmed);
    if (sentences.length <= sentencesPerParagraph) return trimmed;
    final paragraphs = <String>[];
    for (var i = 0; i < sentences.length; i += sentencesPerParagraph) {
      final end = (i + sentencesPerParagraph).clamp(0, sentences.length);
      paragraphs.add(sentences.sublist(i, end).join(' '));
    }
    return paragraphs.join('\n\n');
  }

  /// Oraciones de [text]: corta después de `.`, `?` o `!` seguidos de un
  /// espacio y una mayúscula ("…cartera. En el último año…", "…fuerza.
  /// SGOV se mantuvo…"). No corta siglas de 1-2 letras ("EE. UU.") ni
  /// números ("1.5").
  static List<String> splitSentences(String text) {
    final out = <String>[];
    final boundary = RegExp(r'([.?!])\s+(?=[¿¡]?[A-ZÁÉÍÓÚÑ])');
    var start = 0;
    for (final match in boundary.allMatches(text)) {
      final end = match.start + 1;
      if (_isAbbreviation(text, match.start)) continue;
      final sentence = text.substring(start, end).trim();
      if (sentence.isNotEmpty) out.add(sentence);
      start = match.end;
    }
    final last = text.substring(start).trim();
    if (last.isNotEmpty) out.add(last);
    return out;
  }

  /// La palabra antes del punto en [dot] es una sigla de 1-2 letras ("EE").
  static bool _isAbbreviation(String text, int dot) {
    var i = dot - 1;
    while (i >= 0 && text[i] != ' ') {
      i--;
    }
    return RegExp(r'^[A-ZÁÉÍÓÚÑ]{1,2}$').hasMatch(text.substring(i + 1, dot));
  }

  static final _bullet = RegExp(r'^\s*[•\-–]\s+');

  /// [text] en bloques: párrafos y viñetas, en orden.
  static List<AnswerBlock> blocks(String text) {
    final out = <AnswerBlock>[];
    for (final paragraph in text.split(RegExp(r'\n\s*\n'))) {
      final lines = paragraph.split('\n');
      final prose = <String>[];
      void flush() {
        if (prose.isEmpty) return;
        out.add(AnswerBlock(prose.join('\n'), bullet: false));
        prose.clear();
      }

      for (final line in lines) {
        if (_bullet.hasMatch(line)) {
          flush();
          out.add(AnswerBlock(line.replaceFirst(_bullet, ''), bullet: true));
        } else if (line.trim().isNotEmpty) {
          prose.add(line.trim());
        }
      }
      flush();
    }
    return out;
  }
}

@immutable
class AnswerBlock {
  const AnswerBlock(this.text, {required this.bullet});

  final String text;
  final bool bullet;

  @override
  bool operator ==(Object other) =>
      other is AnswerBlock && other.text == text && other.bullet == bullet;

  @override
  int get hashCode => Object.hash(text, bullet);

  @override
  String toString() => bullet ? '• $text' : text;
}

/// El texto de Porty con sus párrafos y viñetas. Sirve también para un
/// texto a medias (el typewriter, la vista previa del streaming): cada
/// bloque se arma con lo que haya.
class AnswerTextBody extends StatelessWidget {
  const AnswerTextBody({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  static const paragraphGap = 10.0;
  static const bulletGap = 6.0;

  @override
  Widget build(BuildContext context) {
    final blocks = AnswerTextFormat.blocks(text);
    if (blocks.isEmpty) return Text('', style: style);
    final children = <Widget>[];
    for (final (i, block) in blocks.indexed) {
      if (i > 0) {
        final tight = block.bullet && blocks[i - 1].bullet;
        children.add(SizedBox(height: tight ? bulletGap : paragraphGap));
      }
      children.add(
        block.bullet
            ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: style),
                Expanded(child: Text(block.text, style: style)),
              ],
            )
            : Text(block.text, style: style),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

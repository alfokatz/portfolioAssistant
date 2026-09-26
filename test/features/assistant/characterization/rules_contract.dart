import 'package:flutter_test/flutter_test.dart';

/// Caso contrato de reglas de prompt: "una pregunta así → este widget",
/// respaldado por una sección concreta del prompt.
///
/// Son tests de CARACTERIZACIÓN: fijan lo que las reglas de cada modo dicen
/// HOY, antes de unificar Explore + Portfolio + Learn (ver la decisión del
/// 2026-09-25). La suite unificada reusa estos mismos casos contra las
/// reglas nuevas: si un `expectedWidget` cambia, tiene que ser un diff
/// visible y a propósito, nunca una pérdida silenciosa.
///
/// Igual que `explore_prompt_rules_test.dart`, verifican el TEXTO de las
/// reglas, no qué widget elige el modelo (eso queda para el harness de
/// evals contra el modelo, pendiente).
class RuleCase {
  const RuleCase({
    required this.id,
    required this.question,
    required this.section,
    required this.expectedWidgets,
    required this.anchors,
  });

  /// Identificador estable para mapear el caso a la suite unificada.
  final String id;

  /// Pregunta de ejemplo representativa (documentación del caso).
  final String question;

  /// Encabezado de la sección del prompt que decide el caso.
  final String section;

  /// Widgets que esa sección prescribe para la pregunta.
  final List<String> expectedWidgets;

  /// Frases exactas de la regla que respaldan el caso.
  final List<String> anchors;
}

/// Línea de encabezado de sección: todo en mayúsculas, con un paréntesis
/// opcional al final ("LAYOUT (mandatory structure)", "TEMPORAL QUESTIONS
/// (CRITICAL)"). Una línea como "NEVER use total_pnl_abs…" no califica.
final _headerLine = RegExp(r'^[A-Z][A-Z0-9 /&—\-:+.,]+(\s\(.*\))?$');

/// Texto de la sección que arranca en [header], hasta el próximo
/// encabezado.
String ruleSection(String rules, String header) {
  final lines = rules.split('\n');
  final start = lines.indexWhere((l) => l.startsWith(header));
  expect(start, isNonNegative, reason: 'missing section "$header"');
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (_headerLine.hasMatch(lines[i].trim()) && lines[i - 1].trim().isEmpty) {
      end = i;
      break;
    }
  }
  return lines.sublist(start, end).join('\n');
}

/// Registra un test por caso: la sección existe, contiene cada anchor y
/// nombra cada widget esperado.
void verifyRuleCases(String Function() rules, List<RuleCase> cases) {
  for (final c in cases) {
    test('[${c.id}] "${c.question}" → ${c.expectedWidgets.join(' + ')}', () {
      final section = ruleSection(rules(), c.section);
      for (final anchor in c.anchors) {
        expect(section, contains(anchor), reason: 'anchor in ${c.section}');
      }
      for (final widget in c.expectedWidgets) {
        expect(section, contains(widget), reason: 'widget in ${c.section}');
      }
    });
  }
}

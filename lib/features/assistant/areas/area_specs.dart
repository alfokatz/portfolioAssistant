import 'dart:convert';

import 'package:portfolio_assistant/features/assistant/areas/porty_areas.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// Qué prompt usa Porty. `classic` es el de siempre (todo en el prefijo
/// fijo); `lean` saca del prefijo lo que cada área solo necesita después de
/// traer sus datos y lo manda con el resultado de la tool (`area_spec`).
/// Se elige por usuario con `app_config.porty_lean_prompt` (ver
/// `PortyRolloutFlag`), así se mide con evals y se prende sin publicar la
/// app.
enum PromptVariant { classic, lean }

/// El prompt lean y los `area_spec` que lo completan.
abstract final class AreaSpecs {
  /// La regla que el prompt lean agrega después de la de `answer_guide`.
  static const leanRule =
      '- area_spec in a result = the rules and widget schemas for THAT data\n'
      '  (they are not repeated in this prompt): follow them like these\n'
      '  rules. They stay valid while that result is above.\n';

  static const _anchor =
      '- answer_guide in a result says how to answer with THAT data; follow it.\n'
      '  These rules win if they conflict.\n';

  /// Una sección de reglas: desde su encabezado (al principio de una línea)
  /// hasta la línea en blanco que la cierra, sin incluirla.
  static String section(String rules, String heading) {
    final start = rules.indexOf('\n$heading\n');
    if (start < 0) throw StateError('falta la sección "$heading"');
    if (rules.indexOf('\n$heading\n', start + 1) >= 0) {
      throw StateError('la sección "$heading" está dos veces');
    }
    final end = rules.indexOf('\n\n', start + 1);
    if (end < 0) throw StateError('la sección "$heading" no cierra');
    return rules.substring(start + 1, end);
  }

  /// Las reglas lean: las clásicas sin las secciones diferidas y con
  /// [leanRule]. Las clásicas no se tocan (su hash sigue en el allowlist).
  static String leanRules(String classic) {
    if (!classic.contains(_anchor)) {
      throw StateError('no está la regla de answer_guide para anclar');
    }
    var out = classic.replaceFirst(_anchor, '$_anchor$leanRule');
    for (final heading in PortyAreas.deferredRuleSections) {
      out = out.replaceFirst('${section(out, heading)}\n\n', '');
    }
    return out;
  }

  /// El `area_spec` de [tool]: las reglas y esquemas que el prompt lean no
  /// trae. `null` si la tool no difiere nada. [rules] son las reglas
  /// clásicas; [schemas], el esquema de cada widget tal como lo describe el
  /// catálogo (ver [widgetSchemas]).
  static Map<String, Object?>? specFor(
    String tool, {
    required String rules,
    required Map<String, Object?> schemas,
  }) {
    final deferred = PortyAreas.deferredFor(tool);
    if (deferred == null) return null;
    return {
      if (deferred.ruleSections.isNotEmpty)
        'rules': [
          for (final h in deferred.ruleSections) section(rules, h),
        ].join('\n\n'),
      if (deferred.widgets.isNotEmpty)
        'widgets': {for (final w in deferred.widgets) w: schemas[w]},
    };
  }

  /// El esquema de cada componente del catálogo, sacado del
  /// `CATALOG_SCHEMA` del prompt clásico (el mismo texto que el modelo ve
  /// ahí, minificado).
  static Map<String, Object?> widgetSchemas(String classicPrompt) {
    final match = RegExp(
      '-----CATALOG_SCHEMA_START-----\n(.*?)\n-----CATALOG_SCHEMA_END-----',
      dotAll: true,
    ).firstMatch(classicPrompt);
    if (match == null) throw StateError('falta CATALOG_SCHEMA');
    final catalog = jsonDecode(match.group(1)!) as Map<String, Object?>;
    return (catalog['components'] as Map).cast<String, Object?>();
  }

  /// Lo que se suma al resultado de una tool en el prompt lean: el
  /// `area_spec` de la tool, una vez por ventana (si ya está a la vista por
  /// un resultado anterior de la misma tool, no se repite).
  static ResultExtra? extraFor(
    ToolCallRecord record, {
    required String rules,
    required Map<String, Object?> schemas,
  }) {
    final spec = specFor(record.name, rules: rules, schemas: schemas);
    if (spec == null) return null;
    return ResultExtra('area_spec:${record.name}', {'area_spec': spec});
  }
}

import 'dart:convert';

import 'package:genui/genui.dart' show basicCatalogId;

/// Convierte respuestas del LLM al formato A2UI v0.9 esperado por GenUI.
abstract final class A2uiResponseNormalizer {
  /// La constante de genui y no un literal: en 0.10.3 cambió la URL
  /// canónica del catálogo básico, y un id que no matchea ningún catálogo
  /// deja las surfaces sin renderizar, sin ningún error.
  static const defaultCatalogId = basicCatalogId;

  /// [stripCreateSurface]: la surface ya existe, así que cualquier
  /// `createSurface` de la respuesta se descarta.
  ///
  /// [ensureCreateSurface]: la surface todavía no existe, así que si la
  /// respuesta trae `updateComponents` sin `createSurface` se antepone uno.
  /// Pasa en la práctica: después de una ronda de tools, gpt-4.1-mini suele
  /// emitir solo `updateComponents` (verificado en evals), y sin
  /// `createSurface` genui nunca crea la surface.
  static String normalize(
    String raw, {
    required String surfaceId,
    String catalogId = defaultCatalogId,
    bool ensureCreateSurface = false,
    bool stripCreateSurface = false,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    final chunks = _parseJsonChunks(trimmed);
    if (chunks.isEmpty) return trimmed;

    final output = <String>[];
    var hasCreateSurface = false;
    var hasUpdateComponents = false;
    final orphanComponents = <Map<String, dynamic>>[];

    for (final chunk in chunks) {
      if (chunk is Map<String, dynamic>) {
        if (_isA2uiMessage(chunk)) {
          for (final part in _splitOperations(chunk)) {
            var fixed = _withSurfaceId(part, surfaceId);
            final type = _messageType(fixed);
            if (type == 'createSurface') {
              // La surface ya existe (ronda de repair): re-crearla tira
              // "Surface already exists" y tumba el turno entero.
              if (stripCreateSurface) continue;
              hasCreateSurface = true;
            } else if (type == 'updateComponents') {
              final repaired = _repairUpdateComponents(fixed);
              if (repaired != null) {
                fixed = repaired;
                hasUpdateComponents = true;
              }
            }
            output.add(jsonEncode(fixed));
          }
        } else if (_isComponent(chunk)) {
          orphanComponents.add(chunk);
        }
      } else if (chunk is List) {
        for (final item in chunk) {
          if (item is Map<String, dynamic> && _isComponent(item)) {
            orphanComponents.add(item);
          }
        }
      }
    }

    if (orphanComponents.isNotEmpty && !hasUpdateComponents) {
      if (!hasCreateSurface) {
        output.insert(
          0,
          jsonEncode(_createSurface(surfaceId, catalogId)),
        );
      }
      output.add(
        jsonEncode(
          _updateComponents(
            surfaceId,
            _ensureRootColumn(orphanComponents),
          ),
        ),
      );
    }

    if (ensureCreateSurface && hasUpdateComponents && !hasCreateSurface) {
      output.insert(0, jsonEncode(_createSurface(surfaceId, catalogId)));
    }

    return output.isEmpty ? trimmed : output.join('\n');
  }

  /// Fallback A2UI con un componente Text cuando el LLM no devuelve JSON válido.
  static String fallbackResponse(
    String surfaceId,
    String message, {
    String catalogId = defaultCatalogId,
  }) {
    return [
      jsonEncode(_createSurface(surfaceId, catalogId)),
      jsonEncode(
        _updateComponents(surfaceId, [
          {
            'id': 'root',
            'component': 'Text',
            'text': message,
          },
        ]),
      ),
    ].join('\n');
  }

  static List<Object> _parseJsonChunks(String text) {
    final results = <Object>[];
    var remaining = text;

    while (remaining.isNotEmpty) {
      remaining = remaining.trimLeft();
      if (remaining.isEmpty) break;

      final startChar = remaining[0];
      if (startChar != '{' && startChar != '[') {
        final nextObj = remaining.indexOf('{');
        final nextArr = remaining.indexOf('[');
        final next = switch ((nextObj, nextArr)) {
          (-1, -1) => -1,
          (-1, _) => nextArr,
          (_, -1) => nextObj,
          (_, _) => nextObj < nextArr ? nextObj : nextArr,
        };
        if (next == -1) break;
        remaining = remaining.substring(next);
        continue;
      }

      final balanced = _extractBalancedJson(remaining);
      if (balanced == null) break;

      final decoded = _decodeJson(balanced);
      if (decoded != null) results.add(decoded);
      remaining = remaining.substring(balanced.length);
    }

    return results;
  }

  static Object? _decodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static String? _extractBalancedJson(String input) {
    if (input.isEmpty) return null;
    final opener = input[0];
    if (opener != '{' && opener != '[') return null;
    final closer = opener == '{' ? '}' : ']';

    var balance = 0;
    var inString = false;
    var isEscaped = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (isEscaped) {
        isEscaped = false;
        continue;
      }
      if (char == r'\') {
        isEscaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (char == opener) balance++;
        if (char == closer) {
          balance--;
          if (balance == 0) return input.substring(0, i + 1);
        }
      }
    }
    return null;
  }

  static bool _isA2uiMessage(Map<String, dynamic> obj) {
    return obj['version'] == 'v0.9' &&
        (obj.containsKey('createSurface') ||
            obj.containsKey('updateComponents') ||
            obj.containsKey('updateDataModel') ||
            obj.containsKey('deleteSurface'));
  }

  static bool _isComponent(Map<String, dynamic> obj) {
    return obj.containsKey('id') && obj.containsKey('component');
  }

  static const _operations = [
    'createSurface',
    'updateComponents',
    'updateDataModel',
    'deleteSurface',
  ];

  /// A2UI exige exactamente UNA operación por mensaje, pero el modelo a veces
  /// junta `createSurface` + `updateComponents` en un mismo objeto (visto en
  /// rondas de repair). `A2uiMessage.fromJson` tira `A2uiValidationError`
  /// con eso, así que se parte en mensajes separados, en orden canónico.
  static List<Map<String, dynamic>> _splitOperations(
    Map<String, dynamic> chunk,
  ) {
    final present = _operations.where(chunk.containsKey).toList();
    if (present.length <= 1) return [chunk];
    final version = chunk['version'] ?? 'v0.9';
    return [
      for (final op in present) {'version': version, op: chunk[op]},
    ];
  }

  static String? _messageType(Map<String, dynamic> obj) {
    if (obj.containsKey('createSurface')) return 'createSurface';
    if (obj.containsKey('updateComponents')) return 'updateComponents';
    if (obj.containsKey('updateDataModel')) return 'updateDataModel';
    if (obj.containsKey('deleteSurface')) return 'deleteSurface';
    return null;
  }

  static Map<String, dynamic> _withSurfaceId(
    Map<String, dynamic> obj,
    String surfaceId,
  ) {
    final copy = Map<String, dynamic>.from(obj);
    for (final key in [
      'createSurface',
      'updateComponents',
      'updateDataModel',
      'deleteSurface',
    ]) {
      final payload = copy[key];
      if (payload is Map<String, dynamic>) {
        copy[key] = {...payload, 'surfaceId': surfaceId};
      }
    }
    return copy;
  }

  static Map<String, dynamic> _createSurface(
    String surfaceId,
    String catalogId,
  ) =>
      {
        'version': 'v0.9',
        'createSurface': {
          'surfaceId': surfaceId,
          'catalogId': catalogId,
        },
      };

  static Map<String, dynamic> _updateComponents(
    String surfaceId,
    List<Map<String, dynamic>> components,
  ) =>
      {
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': surfaceId,
          'components': components,
        },
      };

  static Map<String, dynamic>? _repairUpdateComponents(
    Map<String, dynamic> message,
  ) {
    final payload = message['updateComponents'];
    if (payload is! Map<String, dynamic>) return null;

    final raw = payload['components'];
    if (raw is! List || raw.isEmpty) return null;

    final components = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (components.isEmpty) return null;

    return {
      ...message,
      'updateComponents': {
        ...payload,
        'components': _ensureRootColumn(components),
      },
    };
  }

  static List<Map<String, dynamic>> _ensureRootColumn(
    List<Map<String, dynamic>> components,
  ) {
    if (components.length == 1 && components.first['id'] == 'root') {
      return components;
    }

    final hasRootColumn = components.any(
      (c) => c['id'] == 'root' && c['component'] == 'Column',
    );
    if (hasRootColumn) return components;

    final childIds = <String>[];
    final normalized = <Map<String, dynamic>>[];

    for (var i = 0; i < components.length; i++) {
      final component = Map<String, dynamic>.from(components[i]);
      if (component['id'] == 'root') {
        component['id'] = 'child_$i';
      }
      childIds.add(component['id'] as String);
      normalized.add(component);
    }

    normalized.insert(0, {
      'id': 'root',
      'component': 'Column',
      'children': childIds,
    });

    return normalized;
  }
}

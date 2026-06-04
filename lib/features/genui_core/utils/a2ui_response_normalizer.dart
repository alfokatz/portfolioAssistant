import 'dart:convert';

/// Convierte respuestas del LLM al formato A2UI v0.9 esperado por GenUI.
abstract final class A2uiResponseNormalizer {
  static const defaultCatalogId =
      'https://a2ui.org/specification/v0_9/standard_catalog.json';

  static String normalize(
    String raw, {
    required String surfaceId,
    String catalogId = defaultCatalogId,
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
          var fixed = _withSurfaceId(chunk, surfaceId);
          final type = _messageType(fixed);
          if (type == 'createSurface') {
            hasCreateSurface = true;
          } else if (type == 'updateComponents') {
            final repaired = _repairUpdateComponents(fixed);
            if (repaired != null) {
              fixed = repaired;
              hasUpdateComponents = true;
            }
          }
          output.add(jsonEncode(fixed));
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

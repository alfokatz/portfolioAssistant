import 'package:dart_openai/dart_openai.dart';

/// Capacidad de datos que el modelo puede pedir vía function calling
/// (Chat Completions `tools`). Nunca renderiza nada: la UI siempre sale del
/// texto A2UI de la ronda final.
///
/// Contrato de [run]:
/// - nunca lanza — una falla es un resultado con `status: failed`, así el
///   turno sigue (el modelo lo redacta) en vez de caerse entero;
/// - el resultado se serializa a JSON y vuelve al modelo como mensaje
///   `tool`, así que tiene que ser chico y sin datos que no deba ver.
abstract interface class DataTool {
  /// Un resultado con este `status` pide que el modelo vuelva a llamar la
  /// misma tool con otros argumentos (el resultado explica cuáles): la
  /// ronda siguiente se fuerza a esa tool, una sola vez por turno.
  static const needsRetryStatus = 'needs_retry';

  /// Estable entre turnos: la lista de tools forma parte del prefijo que
  /// OpenAI cachea.
  String get name;

  String get description;

  /// JSON Schema (`type: object`) de los argumentos.
  Map<String, Object?> get parameters;

  Future<Map<String, Object?>> run(Map<String, Object?> args);
}

extension DataToolOpenAi on DataTool {
  OpenAIToolModel toOpenAi() => OpenAIToolModel(
    type: 'function',
    function: OpenAIFunctionModel(
      name: name,
      description: description,
      parametersSchema: Map<String, dynamic>.from(parameters),
    ),
  );
}

/// Una llamada ya ejecutada dentro de un turno — lo que el provider mira
/// después (peso de cuota, avisos de asesoramiento, paywall).
class ToolCallRecord {
  const ToolCallRecord({
    required this.name,
    required this.args,
    required this.result,
  });

  final String name;
  final Map<String, Object?> args;
  final Map<String, Object?> result;

  String? get status => result['status'] as String?;
}

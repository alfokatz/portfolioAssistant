/// Flag del pipeline unificado (sin modos). Apagado por defecto: con el
/// flag apagado el asistente usa el pipeline por modos intacto.
///
/// Se prende en build con `--dart-define=UNIFIED_ASSISTANT=true`. Invest y
/// Plan siguen siempre con su propio pipeline, con o sin flag.
abstract final class UnifiedAssistantFlag {
  static const bool _fromEnvironment = bool.fromEnvironment(
    'UNIFIED_ASSISTANT',
  );

  static bool? _override;

  static bool get enabled => _override ?? _fromEnvironment;

  /// Solo para tests.
  static set debugOverride(bool? value) => _override = value;
}

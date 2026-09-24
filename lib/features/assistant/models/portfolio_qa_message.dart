import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

/// Mensaje de la conversación Portfolio Q&A (UI).
enum PortfolioQaRole { user, assistant }

class PortfolioQaMessage {
  const PortfolioQaMessage({
    required this.role,
    this.content = '',
    this.surfaceId,
    this.isStreaming = false,
    this.engineMode,
    this.hasRevealed = false,
    this.isFallback = false,
  });

  final PortfolioQaRole role;
  final String content;
  final String? surfaceId;
  final bool isStreaming;

  final AssistantMode? engineMode;

  /// `true` cuando [content] es un mensaje de fallback en texto plano
  /// mostrado porque la generación de esta surface falló, pero [surfaceId]
  /// se conserva a propósito (no se limpia): si un reintento tardío
  /// termina resolviendo esa misma surface con componentes válidos, ese
  /// surfaceId es lo único que permite encontrar este mensaje de nuevo y
  /// reemplazar el error por la respuesta real (ver
  /// `AssistantMessageSync.applySurfaceReady`). Nunca es `true` junto con
  /// `isStreaming`.
  final bool isFallback;

  /// `true` una vez que la surface de este mensaje terminó su reveal
  /// secuencial (ver `SurfaceRevealController.isFullyRevealed`) al menos una
  /// vez. Vive acá, en el modelo, y no en el `State` de ningún widget —
  /// `PortfolioQaAssistantSurface` puede desmontarse y volver a montarse
  /// (scroll fuera y de vuelta al viewport en el `ListView` de la pantalla
  /// de chat) sin que eso dispare de nuevo el typewriter/reveal: el widget
  /// chequea este flag al montar y, si ya está en `true`, renderiza el
  /// contenido final de una en vez de animar.
  final bool hasRevealed;

  /// Si esto debería renderizarse como una `Surface` de GenUI (vs. una
  /// burbuja de texto plano). Un mensaje con `surfaceId` pero marcado
  /// [isFallback] todavía no tiene una surface válida para mostrar — se ve
  /// como texto hasta que, si acaso, un reintento tardío la resuelve.
  bool get isGenUiSurface => surfaceId != null && !isFallback;

  PortfolioQaMessage copyWith({
    PortfolioQaRole? role,
    String? content,
    String? surfaceId,
    bool? isStreaming,
    AssistantMode? engineMode,
    bool? hasRevealed,
    bool? isFallback,
  }) {
    return PortfolioQaMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      surfaceId: surfaceId ?? this.surfaceId,
      isStreaming: isStreaming ?? this.isStreaming,
      engineMode: engineMode ?? this.engineMode,
      hasRevealed: hasRevealed ?? this.hasRevealed,
      isFallback: isFallback ?? this.isFallback,
    );
  }
}

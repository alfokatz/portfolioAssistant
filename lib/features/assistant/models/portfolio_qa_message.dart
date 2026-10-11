/// Mensaje de la conversación Portfolio Q&A (UI).
enum PortfolioQaRole { user, assistant }

/// Aviso bajo una simulación de inversión cuando el perfil de inversor
/// falta o está vencido — ver `AssistantTurnPolicy.noticesFor`.
enum InvestorProfileNudge { missing, stale }

/// Aviso discreto de la app en lugar de una respuesta (no es un error ni
/// un paywall): hoy, el tope diario de consultas del plan.
enum AssistantNotice { dailyLimit }

class PortfolioQaMessage {
  const PortfolioQaMessage({
    required this.role,
    this.content = '',
    this.surfaceId,
    this.isStreaming = false,
    this.hasRevealed = false,
    this.isFallback = false,
    this.showsAdviceDisclaimer = false,
    this.profileNudge,
    this.rememberedFacts = const [],
    this.notice,
  });

  final PortfolioQaRole role;
  final String content;
  final String? surfaceId;
  final bool isStreaming;

  /// Respuesta con sugerencia (simulación de inversión, o meta con
  /// proyección): la
  /// pantalla agrega debajo "sugerencia informativa, no asesoramiento
  /// financiero personalizado". Lo pone la app, no el modelo, para que no
  /// dependa de que el modelo se acuerde de incluirlo.
  final bool showsAdviceDisclaimer;

  /// Si no es `null`, la pantalla agrega el aviso de completar/revisar el
  /// perfil en Ajustes → Perfil de inversor, con link directo.
  final InvestorProfileNudge? profileNudge;

  /// Lo que Porty anotó en su memoria en este turno: la pantalla lo muestra
  /// debajo de la respuesta, con link a "Lo que Porty sabe de vos".
  final List<String> rememberedFacts;

  /// Si no es `null`, la fila muestra este aviso en vez de la respuesta.
  /// Conserva [surfaceId] (misma fila que la espera, que se funde en el
  /// aviso sin saltos de layout).
  final AssistantNotice? notice;

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
  bool get isGenUiSurface =>
      surfaceId != null && !isFallback && notice == null;

  PortfolioQaMessage copyWith({
    PortfolioQaRole? role,
    String? content,
    String? surfaceId,
    bool? isStreaming,
    bool? hasRevealed,
    bool? isFallback,
    bool? showsAdviceDisclaimer,
    InvestorProfileNudge? profileNudge,
    List<String>? rememberedFacts,
    AssistantNotice? notice,
  }) {
    return PortfolioQaMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      surfaceId: surfaceId ?? this.surfaceId,
      isStreaming: isStreaming ?? this.isStreaming,
      hasRevealed: hasRevealed ?? this.hasRevealed,
      isFallback: isFallback ?? this.isFallback,
      showsAdviceDisclaimer:
          showsAdviceDisclaimer ?? this.showsAdviceDisclaimer,
      profileNudge: profileNudge ?? this.profileNudge,
      rememberedFacts: rememberedFacts ?? this.rememberedFacts,
      notice: notice ?? this.notice,
    );
  }
}

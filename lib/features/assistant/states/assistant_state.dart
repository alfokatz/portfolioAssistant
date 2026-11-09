import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/models/chat_paywall.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

class AssistantArgs {
  const AssistantArgs({this.initialQuestion, this.initialScreen});

  /// La conversación de Porty de la sesión: la misma en la pestaña y en el
  /// chat que se abre como hoja sobre otra pantalla (`PortyChatSheet`).
  /// Las preguntas de afuera llegan por `askFromOutside`, no por acá.
  static const session = AssistantArgs();

  final String? initialQuestion;

  /// Desde qué pantalla llegó [initialQuestion] (ver [PortyScreenContext]).
  final PortyScreenContext? initialScreen;
}

/// Una pregunta para Porty que llega desde fuera del chat (chips de Home,
/// detalle de una posición, informe semanal). Es un objeto nuevo en cada
/// toque a propósito, sin `==` por valor: la pestaña de Porty queda montada
/// en el shell, así que la pantalla se entera por `didUpdateWidget` y tiene
/// que distinguir un toque nuevo aunque repita la misma pregunta.
class AssistantQuestionRequest {
  AssistantQuestionRequest(this.question, {this.screen, this.origin});

  final String question;

  /// Quién la tocó, si hace falta medirlo (hoy, solo el widget de la
  /// pantalla de inicio). `null` en el resto de las preguntas de afuera.
  final AssistantQuestionOrigin? origin;

  /// La pantalla desde donde se preguntó; `null` si no es de una en
  /// particular (Home, una notificación).
  final PortyScreenContext? screen;
}

/// De dónde vino una pregunta de afuera, para medir qué pasa con ella
/// (`widget_question_result` al cerrar el turno). No cambia lo que Porty
/// responde ni lo que cuesta: la cuota se descuenta como en cualquier turno.
sealed class AssistantQuestionOrigin {
  const AssistantQuestionOrigin();

  /// Una pregunta tocada en el widget; [questionId] es el id estable del
  /// widget (`today`, `top_mover`), nunca el texto.
  const factory AssistantQuestionOrigin.widget(String questionId) =
      WidgetQuestionOrigin;
}

class WidgetQuestionOrigin extends AssistantQuestionOrigin {
  const WidgetQuestionOrigin(this.questionId);

  final String questionId;
}

/// Estado del asistente: un único hilo de conversación con Porty.
class AssistantState {
  final List<PortfolioQaMessage> messages;
  final String? error;
  final String lastMessage;

  /// Hay un turno en curso. Lo escribe solo `submitMessage`, en el mismo
  /// instante en que toma y suelta su guard: con `true` no se puede enviar
  /// otro mensaje (y la pantalla deshabilita el campo).
  final bool isWaiting;
  final bool bootstrapped;
  final int turnCounter;
  final bool isServiceReady;

  /// El paywall que la pantalla tiene que abrir; `null` si no hay ninguno.
  final ChatPaywall? paywall;

  PaywallReason? get paywallReason => paywall?.reason;
  String? get paywallSource => paywall?.source;
  PlanFeature? get paywallFeature => paywall?.feature;

  /// `true` una vez que la cascada de entrada del saludo inicial + chips de
  /// sugerencia (ver `FadeSlideIn` en `AssistantScreen`) ya se mostró al
  /// menos una vez. Vive acá (no en el `State` de ningún widget) por la
  /// misma razón que `PortfolioQaMessage.hasRevealed`: esos widgets son
  /// items del `ListView` del chat, que los desmonta si scrollean fuera del
  /// cache extent — sin este flag persistente, volver a scrollear hasta
  /// arriba del todo reproduce la cascada de nuevo.
  final bool introRevealed;

  /// En qué quedó cada operación que propuso Porty, por `proposal_id`. Una
  /// propuesta que no está acá sigue pendiente (ver [actionProgress]).
  final Map<String, ActionProposalProgress> actionProposals;

  const AssistantState({
    this.messages = const [],
    this.error,
    this.lastMessage = '',
    this.isWaiting = false,
    this.bootstrapped = false,
    this.turnCounter = 0,
    this.isServiceReady = false,
    this.paywall,
    this.introRevealed = false,
    this.actionProposals = const {},
  });

  ActionProposalProgress actionProgress(String proposalId) =>
      actionProposals[proposalId] ?? ActionProposalProgress.pending;

  AssistantState copyWith({
    List<PortfolioQaMessage>? messages,
    String? error,
    String? lastMessage,
    bool? isWaiting,
    bool? bootstrapped,
    int? turnCounter,
    bool? isServiceReady,
    ChatPaywall? paywall,
    bool? introRevealed,
    Map<String, ActionProposalProgress>? actionProposals,
    bool clearError = false,
    bool clearPaywall = false,
  }) {
    return AssistantState(
      messages: messages ?? this.messages,
      error: clearError ? null : (error ?? this.error),
      lastMessage: lastMessage ?? this.lastMessage,
      isWaiting: isWaiting ?? this.isWaiting,
      bootstrapped: bootstrapped ?? this.bootstrapped,
      turnCounter: turnCounter ?? this.turnCounter,
      isServiceReady: isServiceReady ?? this.isServiceReady,
      paywall: clearPaywall ? null : (paywall ?? this.paywall),
      introRevealed: introRevealed ?? this.introRevealed,
      actionProposals: actionProposals ?? this.actionProposals,
    );
  }
}

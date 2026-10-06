import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/weekly_free_analysis_provider.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_plan_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/reveal_step.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/utils/porty_answer_tone.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_advice_footer.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_composer_field.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_error_banner.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_quiet_notice.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_suggestion_chip.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/message_appear_fade.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_assistant_surface.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_chat_bubble.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_header.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_mood.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/turn_activity.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/top_edge_fade.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';

/// `true` una vez que el avatar del header hizo su entrada en esta sesión de
/// la app: volver al chat no la repite. Global (no autoDispose) a propósito.
final portyChatEntrancePlayedProvider = StateProvider<bool>((ref) => false);

class AssistantScreen extends StatefulHookConsumerWidget {
  const AssistantScreen({super.key, this.initialQuestion});

  final String? initialQuestion;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends BaseStatefulWidget<AssistantScreen>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final AssistantArgs _args;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Auto-tipeo de una sugerencia tocada (ver _startAutoType). `_autoTypingText`
  // es lo último que el propio mecanismo escribió — el listener de
  // _textController lo compara contra el valor actual para detectar que el
  // usuario empezó a escribir por su cuenta y cancelar. `_autoTypeGeneration`
  // desambigua entre una corrida cancelada y una nueva que arrancó después.
  bool _isAutoTyping = false;
  String? _autoTypingText;
  int _autoTypeGeneration = 0;

  static const _autoTypeCharDelay = Duration(milliseconds: 22);

  // Scroll durante un turno: la vista se ancla a la PREGUNTA del usuario.
  // Mientras el turno crece (burbuja del usuario, espera, typewriter, widgets
  // que abren su espacio) la vista acompaña el fondo, pero nunca más allá
  // del punto en que la pregunta toca el borde superior: la pregunta queda
  // visible arriba y la respuesta de Porty empieza justo debajo. Si la
  // respuesta supera el viewport, el resto entra abajo y el usuario scrollea.
  //
  // Cada movimiento es un `animateTo` de [_followDuration]; si el contenido
  // sigue creciendo mientras tanto, al terminar se encadena el siguiente
  // (nunca se reinicia uno a mitad de camino, que se sentía como tirón).
  //
  // El seguimiento se recalcula cada vez que cambia el alto del contenido
  // (`ScrollMetricsNotification`), se corta apenas el usuario arrastra la
  // lista (no se le pisa el scroll) y termina cuando la respuesta terminó
  // su reveal (`PortfolioQaAssistantSurface.onFullyRevealed`) o el turno
  // cerró sin surface (fallback, error, paywall).
  bool _followingTurn = false;
  String? _followSurfaceId;
  String? _questionTileId;
  bool _followScheduled = false;
  bool _animating = false;
  Timer? _finishFollowTimer;
  final _tileKeys = <String, GlobalKey>{};

  /// Alto del fade con que el chat se desvanece contra el header al
  /// scrollear (ver `TopEdgeFade`).
  static const _topFadeExtent = AppDimens.sp20;

  /// Aire entre el borde superior del chat y la pregunta anclada: justo
  /// debajo del fade, así la pregunta nunca queda desvanecida.
  static const _anchorGap = _topFadeExtent;
  static const _followDuration = Duration(milliseconds: 400);
  static const _followCurve = Curves.easeOutCubic;

  /// Tras el fin del reveal, el footer de avisos todavía abre su espacio
  /// ([RevealTiming.entrance]): la última pasada espera a que termine.
  static const _finishFollowDelay = Duration(milliseconds: 650);

  // Alto del composer flotante (incluye margen y safe area), medido en cada
  // layout; la lista lo usa como padding inferior. Ver `_SizeReporter`.
  double _composerInset = 0;

  // La espera de Porty (placeholder del asistente) se agrega al estado
  // en el mismo instante que el mensaje del usuario — pero visualmente debe
  // esperar a que la burbuja del usuario termine su propio typewriter antes
  // de aparecer. `_waitGateOpen` arranca en `false` en cada envío y se abre
  // desde `PortfolioQaChatBubble.onTypingComplete` de esa burbuja. Como los
  // envíos están serializados (guard de UI + `_sendGuard` del provider),
  // nunca hay más de un turno "pendiente de gate" a la vez.
  bool _waitGateOpen = true;

  // Expresión del avatar del header a lo largo del turno (ver PortyMood):
  // thinking mientras corre el turno, answering desde que la respuesta
  // empieza a tipearse hasta que termina el texto, y después answered o
  // idle según si muestra pérdidas; error si el turno no dio respuesta.
  final _mood = PortyMood();
  late final ValueListenable<TurnActivity> _activity;

  /// Surface (placeholder → respuesta) del turno en curso.
  String? _turnSurfaceId;

  /// Surface del turno en curso que está tipeándose (la única cuyo fin de
  /// texto mueve al avatar).
  String? _speakingSurfaceId;

  /// La respuesta del turno ya apareció (o el turno falló): un cambio
  /// tardío de actividad no vuelve a poner a Porty a pensar.
  bool _answerShown = false;

  late final bool _playEntrance = !ref.read(portyChatEntrancePlayedProvider);

  // See HomeScreen: this tab stays mounted alongside Home and Settings in
  // the shell's IndexedStack, so AppShell owns the single subscription.
  @override
  bool get subscribesToGlobalEvents => false;

  @override
  void initState() {
    _args = AssistantArgs(initialQuestion: widget.initialQuestion);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        weight: 45,
        tween: Tween(
          begin: 1.0,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
      ),
      TweenSequenceItem(
        weight: 55,
        tween: Tween(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
      ),
    ]).animate(_pulseController);
    _textController.addListener(_handleTextChanged);
    super.initState();
    _activity = ref.read(assistantProvider(_args).notifier).activity
      ..addListener(_handleActivity);
    if (_playEntrance) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(portyChatEntrancePlayedProvider.notifier).state = true;
        }
      });
    }
    runAfterPostFrameCallback(
      () => ref.read(assistantProvider(_args).notifier).bootstrap(),
    );
  }

  @override
  void dispose() {
    _activity.removeListener(_handleActivity);
    _mood.dispose();
    _finishFollowTimer?.cancel();
    _textController.removeListener(_handleTextChanged);
    _pulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleActivity() {
    if (!_activity.value.isIdle && !_answerShown) _mood.working();
  }

  /// La respuesta del turno empezó a revelarse (la surface dejó de estar en
  /// streaming): Porty habla hasta que termina el texto.
  void _startSpeaking(String surfaceId) {
    _answerShown = true;
    _speakingSurfaceId = surfaceId;
    _mood.speaking();
  }

  /// Terminó el texto de [surfaceId] (o, si no tenía texto, su reveal).
  void _finishSpeaking(AssistantOpenAiService service, String surfaceId) {
    if (surfaceId != _speakingSurfaceId) return;
    _speakingSurfaceId = null;
    final definition = service.controller.contextFor(surfaceId).definition;
    _mood.doneSpeaking(goodNews: !PortyAnswerTone.showsLoss(definition.value));
  }

  /// Sigue el turno en el estado del chat para el avatar del header. El
  /// orden de los cambios no es fijo (el turno puede cerrarse un instante
  /// antes o después de que su respuesta deje de estar en streaming), así
  /// que se sigue la surface del turno por id:
  /// - aparece la respuesta → answering (hasta que termina el texto);
  /// - cae a texto, aviso de tope diario, error o tope de consultas → error;
  /// - el turno cierra sin respuesta ni error (p. ej. paywall de un pedido
  ///   fuera del plan) → idle.
  void _updateMood(AssistantState? previous, AssistantState next) {
    if (previous?.isWaiting != true && next.isWaiting) {
      _answerShown = false;
      _turnSurfaceId = null;
      _speakingSurfaceId = null;
    }
    final last = next.messages.lastOrNull;
    if (next.isWaiting &&
        _turnSurfaceId == null &&
        last != null &&
        last.isStreaming) {
      _turnSurfaceId = last.surfaceId;
    }
    if (_answerShown) return;

    final turn =
        _turnSurfaceId == null
            ? null
            : next.messages
                .where((m) => m.surfaceId == _turnSurfaceId)
                .lastOrNull;
    final failed =
        (next.error != null && previous?.error == null) ||
        (next.paywallReason == PaywallReason.quotaExceeded &&
            previous?.paywallReason != PaywallReason.quotaExceeded) ||
        (turn != null && (turn.isFallback || turn.notice != null));
    if (failed) {
      _answerShown = true;
      _speakingSurfaceId = null;
      _mood.failed();
    } else if (turn != null &&
        turn.isGenUiSurface &&
        !turn.isStreaming &&
        !turn.hasRevealed) {
      _startSpeaking(turn.surfaceId!);
    } else if (!next.isWaiting && (turn == null || !turn.isStreaming)) {
      // Cerró sin nada que mostrar.
      _answerShown = true;
      _mood.rest();
    }
  }

  void _handleTextChanged() {
    if (!_isAutoTyping) return;
    if (_textController.text != _autoTypingText) {
      // El usuario escribió o borró algo distinto de lo que el auto-tipeo
      // puso — se cancela ahí mismo, su texto queda como está.
      _autoTypeGeneration++;
      setState(() {
        _isAutoTyping = false;
        _autoTypingText = null;
      });
    }
  }

  /// Arranca el seguimiento del turno de [surfaceId], anclado a la
  /// pregunta [questionTileId] (id de fila, ver [_tileIdOf]).
  void _followTurn(String surfaceId, String? questionTileId) {
    _finishFollowTimer?.cancel();
    _followingTurn = true;
    _followSurfaceId = surfaceId;
    _questionTileId = questionTileId;
    _scheduleFollow();
  }

  /// Última pasada un toque después de que la respuesta terminó (el footer
  /// de avisos entra recién ahí) y fin del seguimiento.
  void _finishFollowing() {
    if (!_followingTurn) return;
    _finishFollowTimer?.cancel();
    _finishFollowTimer = Timer(_finishFollowDelay, () {
      if (!mounted) return;
      _scheduleFollow(last: true);
    });
  }

  void _stopFollowing() {
    _finishFollowTimer?.cancel();
    _followingTurn = false;
  }

  /// Una sola pasada por frame, después del layout (las posiciones y el
  /// `maxScrollExtent` ya son los finales de ese frame).
  void _scheduleFollow({bool last = false}) {
    if (!_followingTurn) return;
    if (last) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _followNow();
        _followingTurn = false;
      });
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    if (_followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (mounted) _followNow();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _followNow() {
    if (!_followingTurn || !_scrollController.hasClients || _animating) {
      return;
    }
    final position = _scrollController.position;
    var target = position.maxScrollExtent;
    // Si la pregunta todavía no está montada (quedó lejos, abajo, fuera del
    // cache del ListView: el usuario estaba scrolleado arriba o la
    // respuesta anterior era larga), se va al fondo — donde está — y en la
    // próxima pasada ya se puede medir.
    final questionId = _questionTileId;
    final anchor = questionId == null ? null : _tileOffset(questionId);
    if (anchor != null) target = math.min(target, anchor);
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;

    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(target);
      return;
    }
    _animating = true;
    position
        .animateTo(target, duration: _followDuration, curve: _followCurve)
        .whenComplete(() {
          _animating = false;
          // El contenido pudo seguir creciendo durante la animación.
          if (mounted) _scheduleFollow();
        });
  }

  /// Offset de scroll que deja la fila [tileId] a [_anchorGap] del borde
  /// superior. `null` si la fila no está montada.
  double? _tileOffset(String tileId) {
    final box = _tileKeys[tileId]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(box, 0).offset - _anchorGap;
  }

  /// Id estable de la fila de [message] en la posición [index]: el
  /// `surfaceId` para una respuesta; índice + hash del texto para un
  /// mensaje de usuario (dos mensajes con el mismo texto — p. ej. la misma
  /// sugerencia enviada dos veces — antes colisionaban solo con el hash).
  static String _tileIdOf(PortfolioQaMessage message, int index) =>
      message.surfaceId ?? 'user_${index}_${message.content.hashCode}';

  bool _handleScrollNotification(Notification notification) {
    final userDragged = switch (notification) {
      ScrollStartNotification(:final dragDetails) => dragDetails != null,
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (userDragged) {
      _stopFollowing();
    } else if (notification is ScrollMetricsNotification) {
      // El contenido creció (typewriter, card nueva, footer) o cambió el
      // viewport.
      _scheduleFollow();
    }
    return false;
  }

  /// Swap limpio: se limpia el input y el mensaje pasa a existir en el
  /// estado — sin desplazamiento espacial, `MessageAppearFade` en la lista
  /// se encarga del fade corto de entrada. Ambos triggers (sugerencia
  /// auto-tipeada y envío manual) pasan por acá, así se ven consistentes.
  /// La burbuja del usuario se revela con su propio typewriter (ver
  /// `PortfolioQaChatBubble`) — la espera de Porty queda cerrada
  /// (`_waitGateOpen = false`) hasta que ese typewriter avisa que terminó.
  /// Paywall de Gold pedido desde una card (bloque bloqueado, chip con
  /// candado, "Conocer Gold" del análisis de cortesía). Cerrarlo deja el
  /// chat donde estaba (la hoja no toca el scroll). Si compra, la card de
  /// donde vino se completa en el lugar ([AssistantProvider.unlockGoldData]).
  void _openGoldPaywall(AssistantProvider notifier, QaPaywallRequest request) {
    final surfaceId = request.surfaceId;
    final ticker = request.ticker;
    SubscriptionPaywallSheet.show(
      context,
      ref,
      reason: PaywallReason.goldRequired,
      source: request.source,
      preview: request.preview,
      onUpgraded:
          surfaceId == null || ticker == null
              ? null
              : () => notifier.unlockGoldData(surfaceId, ticker),
    );
  }

  Future<void> _submitMessage(AssistantProvider notifier, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.clear();
    setState(() => _waitGateOpen = false);
    await notifier.submitMessage(trimmed);
  }

  /// Escribe [suggestion] en el input carácter por carácter, simulando que
  /// alguien la tipea. Se cancela sola (ver `_handleTextChanged`) si el
  /// usuario escribe algo distinto mientras tanto. Al completarse, pulsa el
  /// botón de enviar y dispara el mismo `_submitMessage` que un envío
  /// manual.
  Future<void> _startAutoType(
    AssistantProvider notifier,
    String suggestion,
  ) async {
    if (_isAutoTyping || ref.read(assistantProvider(_args)).isWaiting) return;

    final generation = ++_autoTypeGeneration;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    setState(() => _isAutoTyping = true);

    if (reduceMotion) {
      _autoTypingText = suggestion;
      _textController.value = TextEditingValue(
        text: suggestion,
        selection: TextSelection.collapsed(offset: suggestion.length),
      );
    } else {
      for (var i = 1; i <= suggestion.length; i++) {
        await Future.delayed(_autoTypeCharDelay);
        if (generation != _autoTypeGeneration || !mounted) return;
        final partial = suggestion.substring(0, i);
        _autoTypingText = partial;
        _textController.value = TextEditingValue(
          text: partial,
          selection: TextSelection.collapsed(offset: partial.length),
        );
      }
    }

    if (generation != _autoTypeGeneration || !mounted) return;
    await _pulseSendButton();
    if (generation != _autoTypeGeneration || !mounted) return;

    _autoTypingText = null;
    setState(() => _isAutoTyping = false);
    await _submitMessage(notifier, suggestion);
  }

  Future<void> _pulseSendButton() async {
    if (MediaQuery.disableAnimationsOf(context)) return;
    await _pulseController.forward(from: 0);
  }

  void _openWaitGate() {
    if (!mounted || _waitGateOpen) return;
    setState(() => _waitGateOpen = true);
  }

  // Guard para no re-programar el post-frame callback de abajo en cada
  // rebuild mientras la intro sigue visible y todavía no se marcó revelada.
  bool _introRevealScheduled = false;

  @override
  Widget buildView(BuildContext context) {
    final state = ref.watch(assistantProvider(_args));
    final notifier = ref.read(assistantProvider(_args).notifier);
    final service = notifier.service;
    final subscription = ref.watch(subscriptionProvider);

    // La cascada de saludo + chips solo se muestra una vez (mientras no hay
    // más que el mensaje de bienvenida) — una vez que arrancó, la marcamos
    // revelada para que un desmontaje/remontaje posterior por scroll (ver
    // `AssistantState.introRevealed`) no la vuelva a animar.
    if (state.messages.length <= 1 &&
        !state.introRevealed &&
        !_introRevealScheduled) {
      _introRevealScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) notifier.markIntroRevealed();
      });
    }

    ref.listen(assistantProvider(_args), (previous, next) {
      final prevLast = previous?.messages.lastOrNull;
      final nextLast = next.messages.lastOrNull;

      _updateMood(previous, next);
      // Terminó de preparar la conversación (ver AssistantProvider.bootstrap,
      // que pone a Porty a pensar mientras tanto).
      if (previous?.isServiceReady == false &&
          next.isServiceReady &&
          !next.isWaiting) {
        _mood.rest();
      }

      // Turno nuevo (envío manual, sugerencia o pregunta inicial): aparece
      // el placeholder en streaming, justo después de la pregunta.
      final turnStarted =
          nextLast != null &&
          nextLast.isStreaming &&
          nextLast.surfaceId != prevLast?.surfaceId;
      if (turnStarted) {
        final questionIndex = next.messages.length - 2;
        final question =
            questionIndex >= 0 ? next.messages[questionIndex] : null;
        _followTurn(
          nextLast.surfaceId!,
          question?.role == PortfolioQaRole.user
              ? _tileIdOf(question!, questionIndex)
              : null,
        );
      } else if (previous?.messages.length != next.messages.length) {
        _scheduleFollow();
      }

      // El turno cerró sin una surface que todavía se esté revelando
      // (fallback de texto, error de conexión, paywall): nadie va a llamar
      // a `onFullyRevealed`, así que el seguimiento se cierra acá.
      if (previous?.isWaiting == true && !next.isWaiting) {
        final revealing =
            nextLast != null &&
            nextLast.isGenUiSurface &&
            !nextLast.hasRevealed;
        if (!revealing) _finishFollowing();
      }

      final reason = next.paywallReason;
      if (reason != null && reason != previous?.paywallReason) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          SubscriptionPaywallSheet.show(
            context,
            ref,
            reason: reason,
            onUpgraded: () => ref.read(subscriptionProvider.notifier).refresh(),
          ).whenComplete(notifier.clearPaywall);
        });
      }
    });

    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: PortyHeader(
              activity: notifier.activity,
              // Durante el turno actúa el avatar del mensaje; el del header
              // queda en reposo y lo que cambia es su línea de estado.
              entrance: _playEntrance,
              quota: PortyQuota(
                remaining: subscription.queriesRemaining,
                limit: subscription.queriesLimit,
              ),
              // El único detalle de cuota que existe es el paywall de
              // "consultas agotadas": solo tiene sentido abrirlo en cero.
              onQuotaTap:
                  subscription.queriesRemaining == 0
                      ? () => SubscriptionPaywallSheet.show(
                        context,
                        ref,
                        reason: PaywallReason.quotaExceeded,
                        onUpgraded:
                            () =>
                                ref
                                    .read(subscriptionProvider.notifier)
                                    .refresh(),
                      )
                      : null,
            ),
          ),
          //const PortfolioQaDisclaimerBanner(),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pageHorizontal,
                vertical: AppDimens.sp4,
              ),
              child: AssistantErrorBanner(
                message: state.error!,
                onRetry:
                    state.isWaiting || state.lastMessage.isEmpty
                        ? null
                        : notifier.clearErrorAndRetry,
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                TopEdgeFade(
                  controller: _scrollController,
                  extent: _topFadeExtent,
                  child: NotificationListener<Notification>(
                    onNotification: _handleScrollNotification,
                    child: ListView(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        AppDimens.pageHorizontal,
                        AppDimens.sp8,
                        AppDimens.pageHorizontal,
                        AppDimens.sp8 + _composerInset,
                      ),
                      children: [
                        for (final (i, m) in state.messages.indexed)
                          MessageAppearFade(
                            skipAnimation: m.hasRevealed,
                            child:
                                service != null
                                    ? _buildMessageTile(
                                      notifier,
                                      service,
                                      m,
                                      index: i,
                                      waitGateOpen: _waitGateOpen,
                                      onUserTypingComplete: () {
                                        _openWaitGate();
                                        notifier.markUserMessageRevealed(i);
                                      },
                                    )
                                    : PortfolioQaChatBubble(
                                      message: m,
                                      onTypingComplete: _openWaitGate,
                                    ),
                          ),
                        if (state.messages.length <= 1) ...[
                          const SizedBox(height: 4),
                          FadeSlideIn(
                            skipAnimation: state.introRevealed,
                            child: Text(
                              'portfolio_qa_chip_intro'.tr(),
                              style: Theme.of(
                                context,
                              ).textTheme.labelMedium?.copyWith(
                                color: PortfolioColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppDimens.sp12),
                          for (final (i, key) in notifier.chipKeys.indexed) ...[
                            if (i > 0) const SizedBox(height: 8),
                            FadeSlideIn(
                              skipAnimation: state.introRevealed,
                              delay: Duration(milliseconds: 60 * (i + 1)),
                              child: AssistantSuggestionChip(
                                label: key.tr(),
                                onTap:
                                    state.isWaiting ||
                                            service == null ||
                                            _isAutoTyping
                                        ? null
                                        : () =>
                                            _startAutoType(notifier, key.tr()),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                // El composer flota sobre la lista (no debajo de ella) para
                // que los mensajes scrolleen por detrás: solo la píldora y el
                // send son opacos, sin franja de fondo alrededor. La lista
                // reserva abajo el alto medido del composer (crece al pasar
                // a multilínea) para que el último mensaje quede visible.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _SizeReporter(
                    onHeightChanged: (h) {
                      if (mounted && h != _composerInset) {
                        setState(() => _composerInset = h);
                      }
                    },
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        // Más aire que el resto de la pantalla (24 vs 20
                        // lateral) para que el composer se lea flotando y no
                        // pegado al borde; ver `input-field-chat` en DESIGN.md.
                        padding: const EdgeInsets.fromLTRB(
                          AppDimens.sp24,
                          AppDimens.sp12,
                          AppDimens.sp24,
                          AppDimens.sp20,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: AssistantComposerField(
                                controller: _textController,
                                hintText: 'portfolio_qa_input_hint'.tr(),
                                onSubmitted:
                                    state.isWaiting || _isAutoTyping
                                        ? null
                                        : (text) =>
                                            _submitMessage(notifier, text),
                                enabled: !state.isWaiting && service != null,
                              ),
                            ),
                            const SizedBox(width: AppDimens.sp8),
                            ScaleTransition(
                              scale: _pulseAnimation,
                              child: AssistantSendButton(
                                onTap:
                                    state.isWaiting ||
                                            service == null ||
                                            _isAutoTyping
                                        ? null
                                        : () => _submitMessage(
                                          notifier,
                                          _textController.text,
                                        ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTile(
    AssistantProvider notifier,
    AssistantOpenAiService service,
    PortfolioQaMessage message, {
    required int index,
    required bool waitGateOpen,
    required VoidCallback onUserTypingComplete,
  }) {
    // Key estable: identifica la fila para el ListView a través de todo su
    // ciclo de vida (espera → respuesta), así el AnimatedSwitcher de abajo
    // conserva su estado entre rebuilds en vez de perder la animación. Es
    // una GlobalKey para que el scroll pueda medir la fila (ver
    // `_tileOffset`).
    final stableKey = _tileKeys.putIfAbsent(
      _tileIdOf(message, index),
      GlobalKey.new,
    );

    late final Key contentKey;
    late final Widget content;

    final notice = message.notice;
    if (notice != null) {
      contentKey = const ValueKey('notice');
      content = AssistantQuietNotice(notice: notice);
    } else if (message.isGenUiSurface &&
        message.isStreaming &&
        !waitGateOpen) {
      // El placeholder ya existe en el estado (se agrega junto con el
      // mensaje del usuario), pero visualmente espera a que la burbuja del
      // usuario termine su propio typewriter antes de mostrar a Porty esperando.
      contentKey = const ValueKey('gated');
      content = const SizedBox.shrink();
    } else if (message.isGenUiSurface && message.isStreaming) {
      // Mientras Porty piensa, la fila es solo su avatar (pulsando, ver
      // _MessageAvatar): el lugar exacto donde va a empezar la respuesta.
      contentKey = const ValueKey('thinking');
      content = const SizedBox(height: _MessageAvatar.size);
    } else if (message.isGenUiSurface) {
      contentKey = const ValueKey('surface');
      final surface = QaPlanScope(
        tier: ref.watch(subscriptionProvider).tier,
        weeklyFreeAnalysisAvailable: ref.watch(
          weeklyFreeAnalysisAvailableProvider,
        ),
        heldTickers: {
          for (final v
              in ref.watch(homeProvider).summary?.valuations ?? const [])
            v.position.ticker.toUpperCase(),
        },
        openPaywall: (request) => _openGoldPaywall(notifier, request),
        child: QaFollowUpScope(
          onFollowUp: (question) => _startAutoType(notifier, question),
          child: QaEvidenceScope(
            lookup: service.evidenceListenable,
            child: PortyVoiceScope(
              onDoneSpeaking:
                  message.surfaceId == _speakingSurfaceId
                      ? () => _finishSpeaking(service, message.surfaceId!)
                      : null,
              child: PortfolioQaAssistantSurface(
                surfaceId: message.surfaceId!,
                surfaceContext: service.controller.contextFor(
                  message.surfaceId!,
                ),
                startFullyRevealed: message.hasRevealed,
                onFullyRevealed: () {
                  if (message.surfaceId == _followSurfaceId) {
                    _finishFollowing();
                  }
                  // Respuesta sin texto: deja de hablar al terminar las cards.
                  _finishSpeaking(service, message.surfaceId!);
                  notifier.markRevealed(message.surfaceId!);
                },
              ),
            ),
          ),
        ),
      );
      // Los avisos fijos (perfil de inversor + disclaimer) entran recién
      // cuando la respuesta terminó su reveal, para no cortar la secuencia.
      content =
          AssistantAdviceFooter.hasContent(message)
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [surface, _AdviceFooterEntrance(message: message)],
              )
              : surface;
    } else {
      contentKey = const ValueKey('bubble');
      content = PortfolioQaChatBubble(
        message: message,
        onTypingComplete:
            message.role == PortfolioQaRole.user ? onUserTypingComplete : null,
      );
    }

    // Crossfade entre lo que ocupa el lugar de la respuesta (espera →
    // respuesta, aviso o fallback), en vez de un swap instantáneo. Con
    // reduce motion el swap es instantáneo (duración cero).
    Widget fade(Key key, Widget child, {Key? switcherKey}) => AnimatedSwitcher(
      key: switcherKey,
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder:
          (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, if (current != null) current],
          ),
      transitionBuilder:
          (child, animation) =>
              FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: key, child: child),
    );

    if (message.role == PortfolioQaRole.user ||
        contentKey == const ValueKey('gated')) {
      return fade(contentKey, content, switcherKey: stableKey);
    }

    // Porty: su avatar a la izquierda, fijo desde que aparece la fila (el
    // mismo lugar y tamaño que en el mensaje final), y el contenido al lado.
    // El avatar del turno en curso actúa (piensa, habla, sonríe); el resto
    // del historial queda quieto.
    final live = message.surfaceId != null && message.surfaceId == _turnSurfaceId;
    final avatar =
        live
            ? ValueListenableBuilder<PortyAvatarState>(
              valueListenable: _mood,
              builder:
                  (context, state, _) =>
                      _MessageAvatar(state: state, animated: true),
            )
            : _MessageAvatar(
              state:
                  message.isFallback || message.notice != null
                      ? PortyAvatarState.error
                      : PortyAvatarState.idle,
            );
    return fade(
      const ValueKey('row'),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: _MessageAvatar.gap),
          Expanded(
            child: Padding(
              // Centra la primera línea del texto con el avatar.
              padding: const EdgeInsets.only(top: _MessageAvatar.textInset),
              child: fade(contentKey, content),
            ),
          ),
        ],
      ),
      switcherKey: stableKey,
    );
  }
}

/// El avatar de Porty al lado de cada respuesta. Quieto en el historial; en
/// el turno en curso piensa con el pulso del chat ([PortyThinkingStyle.pulse])
/// donde va a empezar la respuesta, habla mientras se tipea y sonríe al
/// terminar (o queda en reposo si es una mala noticia).
class _MessageAvatar extends StatefulWidget {
  const _MessageAvatar({required this.state, this.animated = false});

  final PortyAvatarState state;
  final bool animated;

  static const size = 28.0;
  static const gap = 10.0;

  /// La primera línea del texto (15 px × 1,45) queda centrada con el cuerpo.
  static const textInset = 3.0;

  @override
  State<_MessageAvatar> createState() => _MessageAvatarState();
}

class _MessageAvatarState extends State<_MessageAvatar> {
  /// Vuelto a reposo, sigue animado lo que tarda en asentarse (crossfade y
  /// pose) y después queda quieto, como el resto del historial.
  static const _settle = Duration(milliseconds: 500);

  late bool _animating = widget.animated && widget.state != PortyAvatarState.idle;
  Timer? _settleTimer;

  @override
  void didUpdateWidget(_MessageAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = widget.animated && widget.state != PortyAvatarState.idle;
    if (active) {
      _settleTimer?.cancel();
      _animating = true;
    } else if (_animating && widget.animated) {
      _settleTimer ??= Timer(_settle, () {
        _settleTimer = null;
        if (mounted) setState(() => _animating = false);
      });
    } else {
      _settleTimer?.cancel();
      _settleTimer = null;
      _animating = false;
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: PortyAvatar(
      state: widget.state,
      size: _MessageAvatar.size,
      animated: _animating,
      thinkingStyle: PortyThinkingStyle.pulse,
    ),
  );
}

/// El footer de avisos entra último, cuando la respuesta terminó su reveal:
/// fade simple (sin slide ni escala) mientras abre su espacio, así el final
/// de la lista crece en vez de saltar. Si el mensaje ya estaba revelado al
/// montarse (se reconstruyó el historial), aparece directo.
class _AdviceFooterEntrance extends StatefulWidget {
  const _AdviceFooterEntrance({required this.message});

  final PortfolioQaMessage message;

  @override
  State<_AdviceFooterEntrance> createState() => _AdviceFooterEntranceState();
}

class _AdviceFooterEntranceState extends State<_AdviceFooterEntrance> {
  late final bool _revealedAtMount = widget.message.hasRevealed;

  @override
  Widget build(BuildContext context) {
    return RevealEntrance(
      active: widget.message.hasRevealed,
      skip: _revealedAtMount,
      slideDistance: 0,
      scaleFrom: 1,
      child: AssistantAdviceFooter(message: widget.message),
    );
  }
}

/// Reporta el alto de [child] después de cada layout en que cambie.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onHeightChanged, super.child});

  final ValueChanged<double> onHeightChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onHeightChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onHeightChanged = onHeightChanged;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onHeightChanged);

  ValueChanged<double> onHeightChanged;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    // No se puede llamar setState durante layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeightChanged(h));
  }
}

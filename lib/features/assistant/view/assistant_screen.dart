import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/ai_usage_indicator.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_error_banner.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_suggestion_chip.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_thinking_orb.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/message_appear_fade.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_assistant_surface.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_chat_bubble.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';

class AssistantScreen extends StatefulHookConsumerWidget {
  const AssistantScreen({
    super.key,
    this.initialMode = AssistantMode.portfolio,
    this.initialQuestion,
  });

  final AssistantMode initialMode;
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

  // La respuesta de Porty crece después de que ya llegó al estado (ver
  // TypewriterText + RevealStep): el typewriter y las cards en secuencia
  // siguen agregando contenido varios segundos después del único autoscroll
  // que dispara `ref.listen` al resolverse el turno. Sin esto, ese
  // contenido nuevo queda tapado detrás de la barra de input. `_followBottomTimer`
  // persigue el fondo mientras el contenido sigue creciendo.
  //
  // Corte: NO se infiere "terminó de crecer" mirando si `maxScrollExtent`
  // dejó de cambiar por un ratito — una línea de texto que todavía se está
  // tipeando puede tardar más que eso en cruzar a la siguiente línea (el
  // alto del contenido no cambia hasta que hay wrap), así que esa heurística
  // cortaba el seguimiento a mitad de línea, mucho antes de que el
  // typewriter realmente terminara. En su lugar, `_markRevealDone` es la
  // señal explícita (ver `PortfolioQaAssistantSurface.onFullyRevealed`,
  // respaldada por `SurfaceRevealController.isFullyRevealed`) de que la
  // surface entera ya reveló todo su contenido. El tope de ticks que queda
  // es solo una red de seguridad generosa por si esa señal nunca llega
  // (p. ej. un mensaje de usuario, que no pasa por `PortfolioQaAssistantSurface`).
  Timer? _followBottomTimer;
  VoidCallback? _markRevealDone;

  // El orbe de "pensando" (placeholder del asistente) se agrega al estado
  // en el mismo instante que el mensaje del usuario — pero visualmente debe
  // esperar a que la burbuja del usuario termine su propio typewriter antes
  // de aparecer. `_orbGateOpen` arranca en `false` en cada envío y se abre
  // desde `PortfolioQaChatBubble.onTypingComplete` de esa burbuja. Como los
  // envíos están serializados (guard de UI + `_sendGuard` del provider),
  // nunca hay más de un turno "pendiente de gate" a la vez.
  bool _orbGateOpen = true;

  // See HomeScreen: this tab stays mounted alongside Home and Settings in
  // the shell's IndexedStack, so AppShell owns the single subscription.
  @override
  bool get subscribesToGlobalEvents => false;

  @override
  void initState() {
    _args = AssistantArgs(
      initialMode: widget.initialMode,
      initialQuestion: widget.initialQuestion,
    );
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
    runAfterPostFrameCallback(
      () => ref.read(assistantProvider(_args).notifier).bootstrap(),
    );
  }

  @override
  void dispose() {
    _followBottomTimer?.cancel();
    _textController.removeListener(_handleTextChanged);
    _pulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Persigue el fondo de la lista mientras el contenido sigue creciendo
  /// (typewriter de la respuesta + widgets en secuencia + dibujo de chart),
  /// que pasa varios segundos después del único autoscroll que dispara
  /// `ref.listen` al resolverse el turno. Se corta apenas llega la señal
  /// explícita de que terminó (`_markRevealDone`, ver su declaración), o
  /// como red de seguridad, a los 30s.
  void _followBottomWhileRevealing() {
    _followBottomTimer?.cancel();
    var revealDone = false;
    _markRevealDone = () {
      revealDone = true;
      // Pasada extra, un toque después de la señal: `onFullyRevealed`
      // dispara `notifier.markRevealed` (un cambio de estado de Riverpod)
      // en el mismo instante — ese rebuild puede tardar un frame más en
      // asentarse, y la ÚLTIMA pasada del timer de abajo corre en el
      // mismo tick que esta señal, así que puede alcanzar a leer
      // `maxScrollExtent` todavía a mitad de ese asentamiento.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _scrollToBottom();
      });
    };
    var ticksLeft = 250; // 250 * 120ms = 30s de tope, solo por si acaso
    _followBottomTimer = Timer.periodic(const Duration(milliseconds: 120), (
      timer,
    ) {
      if (!mounted || !_scrollController.hasClients) {
        timer.cancel();
        return;
      }
      _scrollToBottom();
      ticksLeft--;
      if (revealDone || ticksLeft <= 0) {
        timer.cancel();
      }
    });
  }

  /// Swap limpio: se limpia el input y el mensaje pasa a existir en el
  /// estado — sin desplazamiento espacial, `MessageAppearFade` en la lista
  /// se encarga del fade corto de entrada. Ambos triggers (sugerencia
  /// auto-tipeada y envío manual) pasan por acá, así se ven consistentes.
  /// La burbuja del usuario se revela con su propio typewriter (ver
  /// `PortfolioQaChatBubble`) — el orbe de "pensando" queda cerrado
  /// (`_orbGateOpen = false`) hasta que ese typewriter avisa que terminó.
  Future<void> _submitMessage(AssistantProvider notifier, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.clear();
    setState(() => _orbGateOpen = false);
    if (!MediaQuery.disableAnimationsOf(context)) {
      _followBottomWhileRevealing();
    }
    await notifier.submitMessage(trimmed);
    _scrollToBottom();
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

  void _openOrbGate() {
    if (!mounted || _orbGateOpen) return;
    setState(() => _orbGateOpen = true);
  }

  // Guard para no re-programar el post-frame callback de abajo en cada
  // rebuild mientras la intro sigue visible y todavía no se marcó revelada.
  bool _introRevealScheduled = false;

  @override
  Widget buildView(BuildContext context) {
    final state = ref.watch(assistantProvider(_args));
    final notifier = ref.read(assistantProvider(_args).notifier);
    final service = notifier.serviceFor(AssistantMode.portfolio);

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
      if (previous?.messages.length != next.messages.length ||
          previous?.isWaiting != next.isWaiting) {
        _scrollToBottom();
      }

      // El último mensaje acaba de dejar de "streamear" (el turno resolvió
      // y el contenido final ya está disponible): arranca ahí el reveal
      // visual (typewriter + cards en secuencia + chart), que sigue
      // creciendo el contenido varios segundos más.
      final prevLast =
          previous?.messages.isNotEmpty == true
              ? previous!.messages.last
              : null;
      final nextLast = next.messages.isNotEmpty ? next.messages.last : null;
      final justStoppedStreaming =
          nextLast != null &&
          nextLast.surfaceId != null &&
          !nextLast.isStreaming &&
          (prevLast == null || prevLast.isStreaming);
      if (justStoppedStreaming && !MediaQuery.disableAnimationsOf(context)) {
        _followBottomWhileRevealing();
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                AppDimens.sp12,
                AppDimens.pageHorizontal,
                AppDimens.sp4,
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PortfolioColors.surfaceElevated,
                      boxShadow: [
                        BoxShadow(
                          color: PortfolioColors.accentBlue.withValues(
                            alpha: 0.18,
                          ),
                          blurRadius: AppDimens.glowBlurSm,
                        ),
                        BoxShadow(
                          color: PortfolioColors.accentWarm.withValues(
                            alpha: 0.16,
                          ),
                          blurRadius: AppDimens.glowBlurSm,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 13,
                      color: PortfolioColors.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'portfolio_qa_title'.tr(),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: PortfolioColors.textSecondary,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const AiUsageIndicator(),
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
                ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.pageHorizontal,
                    AppDimens.sp8,
                    AppDimens.pageHorizontal,
                    AppDimens.sp8,
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
                                  orbGateOpen: _orbGateOpen,
                                  onUserTypingComplete: () {
                                    _openOrbGate();
                                    notifier.markUserMessageRevealed(i);
                                  },
                                )
                                : PortfolioQaChatBubble(
                                  message: m,
                                  onTypingComplete: _openOrbGate,
                                ),
                      ),
                    if (state.messages.length <= 1) ...[
                      const SizedBox(height: 4),
                      FadeSlideIn(
                        skipAnimation: state.introRevealed,
                        child: Text(
                          'portfolio_qa_chip_intro'.tr(),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: PortfolioColors.textSecondary),
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
                                    : () => _startAutoType(notifier, key.tr()),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                if (!state.isServiceReady)
                  const Center(
                    child: AssistantThinkingOrb(size: AppDimens.sp32),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                AppDimens.sp8,
                AppDimens.pageHorizontal,
                AppDimens.sp12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'portfolio_qa_input_hint'.tr(),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PortfolioColors.textPrimary,
                      ),
                      maxLines: 4,
                      minLines: 1,
                      onSubmitted:
                          state.isWaiting || _isAutoTyping
                              ? null
                              : (text) => _submitMessage(notifier, text),
                      enabled: !state.isWaiting && service != null,
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: _SendButton(
                      onTap:
                          state.isWaiting || service == null || _isAutoTyping
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
        ],
      ),
    );
  }

  Widget _buildMessageTile(
    AssistantProvider notifier,
    AssistantOpenAiService fallbackService,
    PortfolioQaMessage message, {
    required int index,
    required bool orbGateOpen,
    required VoidCallback onUserTypingComplete,
  }) {
    // Key estable: identifica la fila para el ListView a través de todo su
    // ciclo de vida (orbe → respuesta), así el AnimatedSwitcher de abajo
    // conserva su estado entre rebuilds en vez de perder la animación. Para
    // mensajes de usuario (sin surfaceId) se incluye el índice: dos
    // mensajes con el mismo texto (p. ej. la misma sugerencia enviada dos
    // veces) antes colisionaban en la misma key solo con el hash del
    // contenido.
    final stableKey = ValueKey(
      message.surfaceId ?? 'user_${index}_${message.content.hashCode}',
    );

    late final Key contentKey;
    late final Widget content;

    if (message.isGenUiSurface && message.isStreaming && !orbGateOpen) {
      // El placeholder ya existe en el estado (se agrega junto con el
      // mensaje del usuario), pero visualmente espera a que la burbuja del
      // usuario termine su propio typewriter antes de mostrar el orbe.
      contentKey = const ValueKey('gated');
      content = const SizedBox.shrink();
    } else if (message.isGenUiSurface && message.isStreaming) {
      // Sin chrome de burbuja: el orbe flota suelto en el lugar donde va a
      // aparecer la respuesta, en vez de quedar encerrado en un contenedor.
      // Sin deriva vertical: acá el orbe marca un punto exacto — dónde va
      // a aparecer la respuesta — y alejarse de ese punto contradice esa
      // promesa espacial.
      contentKey = const ValueKey('thinking');
      content = Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.sp12),
        child: const Align(
          alignment: Alignment.centerLeft,
          child: AssistantThinkingOrb(size: AppDimens.iconLg),
        ),
      );
    } else if (message.isGenUiSurface) {
      contentKey = const ValueKey('surface');
      final surfaceService =
          message.engineMode == null
              ? fallbackService
              : (notifier.serviceFor(message.engineMode!) ?? fallbackService);
      content = PortfolioQaAssistantSurface(
        surfaceId: message.surfaceId!,
        surfaceContext: surfaceService.controller.contextFor(
          message.surfaceId!,
        ),
        startFullyRevealed: message.hasRevealed,
        onFullyRevealed: () {
          _markRevealDone?.call();
          notifier.markRevealed(message.surfaceId!);
        },
      );
    } else {
      contentKey = const ValueKey('bubble');
      content = PortfolioQaChatBubble(
        message: message,
        onTypingComplete:
            message.role == PortfolioQaRole.user ? onUserTypingComplete : null,
      );
    }

    // El orbe no tenía salida propia: al llegar la respuesta, desaparecía de
    // golpe reemplazado por la card. El crossfade acá hace que se desvanezca
    // mientras la card entra, en vez de un swap instantáneo y desconectado.
    return AnimatedSwitcher(
      key: stableKey,
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder:
          (child, animation) =>
              FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: contentKey, child: content),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        boxShadow:
            enabled
                ? [
                  BoxShadow(
                    color: PortfolioColors.accentBlue.withValues(alpha: 0.30),
                    blurRadius: AppDimens.glowBlurSm,
                  ),
                  BoxShadow(
                    color: PortfolioColors.accentWarm.withValues(alpha: 0.22),
                    blurRadius: AppDimens.glowBlurMd,
                  ),
                ]
                : null,
      ),
      child: Material(
        color:
            enabled
                ? PortfolioColors.accentBlue
                : PortfolioColors.accentBlue.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.arrow_upward_rounded,
              color: PortfolioColors.textPrimary,
              size: AppDimens.iconMd,
            ),
          ),
        ),
      ),
    );
  }
}

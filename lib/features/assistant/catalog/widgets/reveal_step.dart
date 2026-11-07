import 'dart:async';

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/presentation/shared/animation/reveal_animation.dart';

/// Tiempos y curvas del reveal de una respuesta de Porty. Todo en un solo
/// lugar para poder ajustarlo a ojo.
abstract final class RevealTiming {
  /// Pausa entre el fin del typewriter y la entrada del primer widget.
  static const gapAfterText = Duration(milliseconds: 200);

  /// Desfase entre el INICIO de la entrada de un widget y el del siguiente:
  /// las entradas se solapan, no se esperan.
  static const stagger = Duration(milliseconds: 160);

  /// Duración total de la entrada de un widget ([RevealEntrance]).
  static const entrance = Duration(milliseconds: 460);

  /// Tramo inicial de [entrance] en el que se abre el espacio del widget
  /// (lo de abajo se desliza en vez de saltar).
  static const sizeOpen = Duration(milliseconds: 300);

  /// El fade + slide arranca apenas después de que el espacio empezó a
  /// abrirse, así el widget "aparece en" un hueco que ya se está abriendo.
  static const appearDelay = Duration(milliseconds: 60);

  /// Desplazamiento vertical inicial (hacia arriba al entrar).
  static const slideDistance = 14.0;

  /// Escala inicial; 1 = sin escala.
  static const scaleFrom = 0.98;

  /// Curva de apertura de espacio, slide y escala.
  static const motionCurve = Curves.easeOutCubic;

  /// Curva de opacidad: `easeOut` (cúbica suave) en vez de `easeOutCubic`,
  /// que llega al ~70% de opacidad en el primer tercio y se lee como "pop".
  static const opacityCurve = Curves.easeOut;

  /// Llenado de indicadores numéricos (anillo de encaje) al entrar la card.
  static const fill = Duration(milliseconds: 600);
}

/// Qué vibraciones acompañan el reveal de una surface.
enum RevealHaptics {
  /// Mensaje nuevo con animaciones: golpe al arrancar cada widget, clic al
  /// asentarse y el cierre.
  full,

  /// Mensaje nuevo con reduce motion: solo el cierre ("respuesta lista").
  closeOnly,

  /// Surface reconstruida (ya se había revelado): nada.
  none,
}

/// Orquesta el reveal de los widgets de una surface GenUI: el texto de
/// Porty primero (typewriter), después cada widget con su entrada animada,
/// escalonados y solapados — en vez de aparecer todos juntos.
///
/// Cada [RevealStep] reclama un slot autoincremental al montarse
/// ([claimSlot]) — como Flutter construye los hijos de una `Column` en
/// orden durante el mismo frame, el orden de montaje coincide con el orden
/// en que la IA autoró los widgets, sin necesidad de pasarle índices a
/// mano.
///
/// Cómo se desbloquea el siguiente slot:
/// - Un paso "bloqueante" (el texto con typewriter, o cualquier
///   [RevealStep] genérico) lo desbloquea [RevealTiming.gapAfterText]
///   después de terminar ([advance]).
/// - Un widget ([RevealStep.fade]/[RevealStep.entrance]) lo desbloquea
///   [RevealTiming.stagger] después de EMPEZAR su entrada ([stepStarted]).
///
/// También es el único lugar que decide los haptics del reveal (ver
/// [RevealHaptics] y `PortyHapticsService`): conoce el orden y el total de
/// widgets de la respuesta, que ningún widget suelto conoce.
class SurfaceRevealController extends ChangeNotifier {
  SurfaceRevealController({
    this.reduceMotion = false,
    this.haptics,
    RevealHaptics? hapticsMode,
  }) : hapticsMode =
           hapticsMode ??
           (reduceMotion ? RevealHaptics.none : RevealHaptics.full),
       _readyIndex = reduceMotion ? _unlockedAll : 0;

  static const _unlockedAll = 1 << 30;

  final bool reduceMotion;
  final PortyHapticsService? haptics;
  final RevealHaptics hapticsMode;
  int _readyIndex;
  int _nextSlot = 0;
  final _widgetSlots = <int>[];
  final _finished = <int>{};
  final _timers = <Timer>[];
  bool _completed = false;
  bool _disposed = false;

  /// Reclama el próximo slot disponible. Se llama una sola vez por
  /// [RevealStep], en su `initState`. [isWidget] marca los widgets del
  /// catálogo (cards), que entran solapados y vibran; el resto bloquea.
  int claimSlot({bool isWidget = false}) {
    final slot = _nextSlot++;
    if (isWidget) _widgetSlots.add(slot);
    return slot;
  }

  bool isReady(int slot) => slot <= _readyIndex;

  /// `true` una vez que TODOS los pasos reclamados terminaron su propia
  /// entrada (no solo que les tocó el turno). Como Flutter monta todos los
  /// `RevealStep` de una surface en el mismo frame (ver arriba), `_nextSlot`
  /// ya vale su total final desde el primer build — este getter es, por
  /// eso, una señal exacta de "la surface entera terminó de revelarse".
  bool get isFullyRevealed => _nextSlot > 0 && _finished.length >= _nextSlot;

  /// El widget de [slot] arrancó su entrada (mismo frame en que empieza a
  /// moverse): vibra, y programa el turno del siguiente con el desfase.
  /// Puede llamarse durante el build: no notifica sincrónicamente.
  void stepStarted(int slot) {
    if (hapticsMode == RevealHaptics.full && _widgetSlots.contains(slot)) {
      haptics?.widgetEntryStarted();
    }
    if (!reduceMotion && slot == _readyIndex) {
      _unlockAfter(slot + 1, RevealTiming.stagger);
    }
  }

  /// El paso [slot] terminó su entrada. Si todavía bloqueaba al siguiente,
  /// lo desbloquea (al instante para un widget; con pausa tras el texto).
  void advance(int slot) {
    if (_disposed || !_finished.add(slot)) return;
    final isWidget = _widgetSlots.contains(slot);
    if (!reduceMotion && slot == _readyIndex) {
      _unlockAfter(
        slot + 1,
        isWidget ? Duration.zero : RevealTiming.gapAfterText,
      );
    }
    if (isFullyRevealed && !_completed) {
      // El último en asentarse cierra la respuesta: el cierre reemplaza su
      // clic (dos vibraciones juntas se sentirían como una sola, borrosa).
      _completed = true;
      _announceComplete();
    } else if (isWidget && hapticsMode == RevealHaptics.full) {
      haptics?.widgetEntrySettled();
    }
    notifyListeners();
  }

  void _unlockAfter(int next, Duration delay) {
    if (delay == Duration.zero) {
      _unlock(next);
      return;
    }
    _timers.add(Timer(delay, () => _unlock(next)));
  }

  void _unlock(int next) {
    if (_disposed || next <= _readyIndex) return;
    _readyIndex = next;
    notifyListeners();
  }

  void _announceComplete() {
    final haptics = this.haptics;
    if (haptics == null || hapticsMode == RevealHaptics.none) return;
    if (_widgetSlots.isEmpty) {
      // Solo texto: el comportamiento de siempre (un toque leve al terminar
      // de tipear), sin cierre especial.
      if (hapticsMode == RevealHaptics.full) haptics.textAnswerRevealed();
      return;
    }
    haptics.answerRevealCompleted();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }
}

/// Un paso del reveal secuencial. Reclama su slot al montar y renderiza
/// [builder] con `active` (si ya le toca el turno) y `onFinished` (a llamar
/// cuando termine su propia animación de entrada, para desbloquear el
/// siguiente paso).
class RevealStep extends StatefulWidget {
  const RevealStep({super.key, required this.controller, required this.builder})
    : _isWidget = false,
      _innerFinishes = true;

  /// Un widget del catálogo con contenido ya armado (cualquier card): entra
  /// con [RevealEntrance] cuando le toca el turno.
  RevealStep.fade({super.key, required this.controller, required Widget child})
    : builder = ((context, active, onFinished) => child),
      _isWidget = true,
      _innerFinishes = false;

  /// Un widget con reveal interno propio (dibujo de un chart, "título antes
  /// que valores"): entra con [RevealEntrance] y [builder] recibe `active`
  /// en el mismo frame en que arranca la entrada. El paso termina cuando
  /// terminaron la entrada Y el reveal interno (`onFinished`).
  const RevealStep.entrance({
    super.key,
    required this.controller,
    required this.builder,
  }) : _isWidget = true,
       _innerFinishes = true;

  final SurfaceRevealController controller;
  final Widget Function(
    BuildContext context,
    bool active,
    VoidCallback onFinished,
  )
  builder;

  final bool _isWidget;

  /// Si [builder] llama a su `onFinished` (vs. contenido estático).
  final bool _innerFinishes;

  @override
  State<RevealStep> createState() => _RevealStepState();
}

class _RevealStepState extends State<RevealStep> {
  late final int _slot;
  bool _entranceDone = false;
  late bool _innerDone;

  @override
  void initState() {
    super.initState();
    _slot = widget.controller.claimSlot(isWidget: widget._isWidget);
    _innerDone = !widget._innerFinishes;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleFinished() => widget.controller.advance(_slot);

  void _handleInnerFinished() {
    _innerDone = true;
    if (_entranceDone) _handleFinished();
  }

  void _handleEntranceFinished() {
    _entranceDone = true;
    if (_innerDone) _handleFinished();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller.isReady(_slot);
    if (!widget._isWidget) {
      return widget.builder(context, active, _handleFinished);
    }
    return RevealEntrance(
      active: active,
      skip: widget.controller.reduceMotion,
      onStarted: () => widget.controller.stepStarted(_slot),
      onFinished: _handleEntranceFinished,
      child: widget.builder(context, active, _handleInnerFinished),
    );
  }
}

/// Entrada única de todo widget de una respuesta de Porty: mientras no le
/// toca, ocupa 0 de alto (lo de abajo no reserva un hueco invisible); al
/// activarse, abre su espacio ([RevealTiming.sizeOpen]) y, apenas después,
/// hace fade + slide corto hacia arriba + escala 0.98→1. Todo con un solo
/// `AnimationController`.
///
/// El hijo está montado desde el principio (se construye, carga logos,
/// reclama sus slots), solo que colapsado e invisible. Con [skip] (reduce
/// motion, o una surface que ya se reveló antes) aparece en su lugar final
/// de una, sin animación.
///
/// Expone [RevealEntranceScope] para que indicadores del kit (anillo de
/// encaje, barras) arranquen su llenado junto con la entrada.
class RevealEntrance extends StatefulWidget {
  const RevealEntrance({
    super.key,
    required this.active,
    required this.child,
    this.skip = false,
    this.onStarted,
    this.onFinished,
    this.slideDistance = RevealTiming.slideDistance,
    this.scaleFrom = RevealTiming.scaleFrom,
  });

  final bool active;
  final Widget child;
  final bool skip;

  /// Se llama en el mismo frame en que arranca la entrada (o en que se
  /// muestra de una, con [skip]).
  final VoidCallback? onStarted;

  /// Se llama al terminar la entrada (post-frame con [skip]).
  final VoidCallback? onFinished;
  final double slideDistance;
  final double scaleFrom;

  @override
  State<RevealEntrance> createState() => _RevealEntranceState();
}

class _RevealEntranceState extends State<RevealEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _size;
  late final Animation<double> _motion;
  late final Animation<double> _opacity;
  bool _started = false;
  bool _skipped = false;
  bool _finished = false;

  static double _fraction(Duration d) =>
      d.inMicroseconds / RevealTiming.entrance.inMicroseconds;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: RevealTiming.entrance,
    )..addStatusListener(_handleStatus);
    _size = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        0,
        _fraction(RevealTiming.sizeOpen),
        curve: RevealTiming.motionCurve,
      ),
    );
    final appearStart = _fraction(RevealTiming.appearDelay);
    _motion = CurvedAnimation(
      parent: _controller,
      curve: Interval(appearStart, 1, curve: RevealTiming.motionCurve),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Interval(appearStart, 1, curve: RevealTiming.opacityCurve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant RevealEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStart();
  }

  void _maybeStart() {
    if (_started || !widget.active) return;
    _started = true;
    _skipped = widget.skip || MediaQuery.disableAnimationsOf(context);
    widget.onStarted?.call();
    startRevealAnimation(
      _controller,
      skip: _skipped,
      statusListener: _handleStatus,
      isMounted: () => mounted,
    );
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_finished) {
      _finished = true;
      widget.onFinished?.call();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RevealEntranceScope(
      started: _started,
      skip: _skipped,
      child: AnimatedBuilder(
        animation: _controller,
        // El contenido de la card no cambia mientras entra: con su propia
        // capa, cada frame solo recompone opacidad/transform en vez de
        // repintarla.
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) {
          final size = _size.value;
          final motion = _motion.value;
          return ClipRect(
            // Solo recorta mientras el espacio se abre: ya abierta, la
            // sombra de la card no queda cortada. Mismo tipo de widget
            // siempre, para no remontar el hijo.
            clipBehavior: size < 1 ? Clip.hardEdge : Clip.none,
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: size,
              child: Opacity(
                opacity: _opacity.value,
                child: Transform.translate(
                  offset: Offset(0, (1 - motion) * widget.slideDistance),
                  child: Transform.scale(
                    scale: widget.scaleFrom + (1 - widget.scaleFrom) * motion,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Estado de la [RevealEntrance] más cercana, para que un indicador
/// numérico del kit (ver [EntranceFill]) se llene recién cuando su widget
/// entra, y no al montarse invisible.
class RevealEntranceScope extends InheritedWidget {
  const RevealEntranceScope({
    super.key,
    required this.started,
    required this.skip,
    required super.child,
  });

  final bool started;
  final bool skip;

  static RevealEntranceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RevealEntranceScope>();

  @override
  bool updateShouldNotify(RevealEntranceScope oldWidget) =>
      started != oldWidget.started || skip != oldWidget.skip;
}

/// Progreso 0→1 del llenado de un indicador (anillo, barra), atado a la
/// entrada de su widget: en 0 mientras el widget no entró, anima al entrar,
/// y salta a 1 con reduce motion o en una surface ya revelada (no se
/// re-anima al reconstruir). Fuera de una respuesta (sin
/// [RevealEntranceScope]) anima al montarse, como siempre.
class EntranceFill extends StatelessWidget {
  const EntranceFill({
    super.key,
    required this.duration,
    required this.builder,
    this.curve = RevealTiming.motionCurve,
    this.child,
  });

  final Duration duration;
  final Curve curve;
  final ValueWidgetBuilder<double> builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scope = RevealEntranceScope.maybeOf(context);
    final skip =
        (scope?.skip ?? false) || MediaQuery.disableAnimationsOf(context);
    final target = scope == null || scope.started || skip ? 1.0 : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: skip ? Duration.zero : duration,
      curve: curve,
      builder: builder,
      child: child,
    );
  }
}

/// Expone el [SurfaceRevealController] de la surface actual a los widgets
/// del catálogo que se rendericen por debajo — son widgets Flutter comunes
/// con su propio `BuildContext` (independiente del `CatalogItemContext` que
/// les pasa el paquete `genui`), así que pueden leerlo con `context` normal.
class SurfaceRevealScope extends InheritedWidget {
  const SurfaceRevealScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SurfaceRevealController controller;

  /// `null` si no hay ninguna surface ancestro (p. ej. un catalog widget
  /// usado fuera de `PortfolioQaAssistantSurface`, como en un test aislado)
  /// — quien llama decide el fallback (no revelar en pasos, mostrar directo).
  static SurfaceRevealController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SurfaceRevealScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(SurfaceRevealScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Reveal interno de dos etapas ("título" y "valor") dentro de una sola
/// card — para el caso "primero el label, después el número" sin necesitar
/// un [SurfaceRevealController] anidado completo. Arranca cuando [active]
/// pasa a `true` (típicamente el `active` que ya provee el `RevealStep`
/// exterior de la card, vía `QaCardShell.staged`) y llama [onFinished]
/// cuando ambas etapas terminaron — recién ahí la card exterior deja pasar
/// a la siguiente.
class TwoStageReveal extends StatefulWidget {
  const TwoStageReveal({
    super.key,
    required this.active,
    required this.first,
    required this.second,
    this.onFinished,
    this.duration = const Duration(milliseconds: 260),
  });

  final bool active;
  final Widget first;
  final Widget second;
  final VoidCallback? onFinished;
  final Duration duration;

  @override
  State<TwoStageReveal> createState() => _TwoStageRevealState();
}

class _TwoStageRevealState extends State<TwoStageReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _firstOpacity;
  late final Animation<double> _secondOpacity;
  bool _started = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener(_handleStatus);
    _firstOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    );
    _secondOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant TwoStageReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStart();
  }

  void _maybeStart() {
    if (_started || !widget.active) return;
    _started = true;
    startRevealAnimation(
      _controller,
      skip: MediaQuery.disableAnimationsOf(context),
      statusListener: _handleStatus,
      isMounted: () => mounted,
    );
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_finished) {
      _finished = true;
      widget.onFinished?.call();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(opacity: _firstOpacity, child: widget.first),
        FadeTransition(opacity: _secondOpacity, child: widget.second),
      ],
    );
  }
}

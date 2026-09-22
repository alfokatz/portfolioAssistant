import 'package:flutter/material.dart';

/// Orquesta el reveal secuencial de los widgets de una surface GenUI:
/// título/texto primero, después el widget de datos, después el banner de
/// tip, etc. — en vez de aparecer todos juntos.
///
/// Cada [RevealStep] reclama un slot autoincremental al montarse
/// ([claimSlot]) — como Flutter construye los hijos de una `Column` en
/// orden durante el mismo frame, el orden de montaje coincide con el orden
/// en que la IA autoró los widgets, sin necesidad de pasarle índices a
/// mano. [advance] desbloquea el siguiente slot recién cuando el paso
/// actual terminó su propia entrada (typewriter, fade, dibujo de chart).
///
/// Es genérico y agnóstico del contenido — vive en el catálogo para que
/// cualquier widget de cualquiera de los modos (portfolio/learn/explore/
/// invest/plan, que comparten un único catálogo) lo pueda reusar, y también
/// se puede anidar: una card puede crear su propio `SurfaceRevealController`
/// chico para su reveal interno ("título antes que valores"), encadenado a
/// que la card exterior ya haya sido revelada.
class SurfaceRevealController extends ChangeNotifier {
  SurfaceRevealController({this.reduceMotion = false})
    : _readyIndex = reduceMotion ? _unlockedAll : 0;

  static const _unlockedAll = 1 << 30;

  final bool reduceMotion;
  int _readyIndex;
  int _nextSlot = 0;

  /// Reclama el próximo slot disponible. Se llama una sola vez por
  /// [RevealStep], en su `initState`.
  int claimSlot() => _nextSlot++;

  bool isReady(int slot) => slot <= _readyIndex;

  /// El paso [slot] terminó su entrada — si es el que estaba bloqueando el
  /// avance, desbloquea el siguiente.
  void advance(int slot) {
    if (reduceMotion) return; // ya está todo desbloqueado
    if (slot == _readyIndex) {
      _readyIndex = slot + 1;
      notifyListeners();
    }
  }
}

/// Un paso del reveal secuencial. Reclama su slot al montar y renderiza
/// [builder] con `active` (si ya le toca el turno) y `onFinished` (a llamar
/// cuando termine su propia animación de entrada, para desbloquear el
/// siguiente paso).
class RevealStep extends StatefulWidget {
  const RevealStep({super.key, required this.controller, required this.builder});

  /// Reveal por defecto para pasos que no necesitan una entrada a medida
  /// (cualquier card que ya tenga su propio contenido armado): un fade-in
  /// simple (~180ms `easeOutCubic`) cuando le toca el turno.
  RevealStep.fade({
    super.key,
    required this.controller,
    required Widget child,
    Duration duration = const Duration(milliseconds: 180),
  }) : builder =
           ((context, active, onFinished) => _DefaultFadeStep(
             active: active,
             duration: duration,
             onFinished: onFinished,
             child: child,
           ));

  final SurfaceRevealController controller;
  final Widget Function(
    BuildContext context,
    bool active,
    VoidCallback onFinished,
  )
  builder;

  @override
  State<RevealStep> createState() => _RevealStepState();
}

class _RevealStepState extends State<RevealStep> {
  late final int _slot;

  @override
  void initState() {
    super.initState();
    _slot = widget.controller.claimSlot();
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

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      widget.controller.isReady(_slot),
      _handleFinished,
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
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
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

class _DefaultFadeStep extends StatefulWidget {
  const _DefaultFadeStep({
    required this.active,
    required this.duration,
    required this.onFinished,
    required this.child,
  });

  final bool active;
  final Duration duration;
  final VoidCallback onFinished;
  final Widget child;

  @override
  State<_DefaultFadeStep> createState() => _DefaultFadeStepState();
}

class _DefaultFadeStepState extends State<_DefaultFadeStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener(_handleStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `MediaQuery.disableAnimationsOf` depende de un InheritedWidget, que no
    // se puede leer desde `initState` — acá es el lugar seguro más temprano
    // (mismo criterio que `PortfolioQaAssistantSurface`).
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant _DefaultFadeStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStart();
  }

  void _maybeStart() {
    if (_started || !widget.active) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_finished) {
      _finished = true;
      widget.onFinished();
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
    // No activo todavía: invisible pero con su espacio reservado, para que
    // el resto del layout no salte cuando le toque aparecer.
    if (!_started) return Opacity(opacity: 0, child: widget.child);
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      child: widget.child,
    );
  }
}

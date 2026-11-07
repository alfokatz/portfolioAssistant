import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';

/// Cambia entre secciones con un "fade through": la saliente se desvanece
/// por completo y recién ahí entra la nueva (fade + un desplazamiento corto
/// en la dirección del cambio). Nunca hay dos secciones visibles a la vez,
/// a diferencia de un `AnimatedSwitcher`, que apila saliente y entrante en
/// un crossfade.
///
/// Las secciones ya construidas quedan vivas fuera de escena ([Offstage] +
/// [TickerMode] apagado): volver a una no la reconstruye ni rehace su
/// trabajo, y cambiar de sección no construye nada pesado en medio de la
/// animación. Con [prebuild], las secciones todavía no vistas se construyen
/// un frame después del primero, fuera del camino de cualquier animación.
///
/// El cambio de alto entre secciones se anima ([AnimatedSize]) para que lo
/// que hay debajo no salte. Con reduce motion el cambio es instantáneo.
class FadeThroughSwitcher extends StatefulWidget {
  const FadeThroughSwitcher({
    super.key,
    required this.index,
    required this.builders,
    this.prebuild = true,
  });

  final int index;
  final List<WidgetBuilder> builders;
  final bool prebuild;

  static const fadeOutDuration = Duration(milliseconds: 90);
  static const fadeInDuration = Duration(milliseconds: 160);
  static const sizeDuration = Duration(milliseconds: 220);

  /// Desplazamiento horizontal con que entra la nueva sección.
  static const slideDistance = 8.0;

  @override
  State<FadeThroughSwitcher> createState() => _FadeThroughSwitcherState();
}

class _FadeThroughSwitcherState extends State<FadeThroughSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    value: 1,
  );

  /// La sección en escena. Durante el fade-out sigue siendo la anterior.
  late int _shown = widget.index;
  late final Set<int> _built = {widget.index};

  /// +1 si la nueva sección está a la derecha de la anterior, -1 si no.
  double _direction = 1;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.prebuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          for (var i = 0; i < widget.builders.length; i++) {
            _built.add(i);
          }
        });
      });
    }
  }

  @override
  void didUpdateWidget(FadeThroughSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) _switchTo(widget.index);
  }

  @override
  void dispose() {
    _opacity.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  Future<void> _switchTo(int target) async {
    final generation = ++_generation;
    _built.add(target);
    if (_reduceMotion) {
      _opacity.value = 1;
      setState(() => _shown = target);
      return;
    }
    if (_opacity.value > 0 && _shown != target) {
      // Si el usuario vuelve a tocar a mitad de un cambio, se sale desde la
      // opacidad actual en vez de saltar.
      await _opacity.animateTo(
        0,
        duration: FadeThroughSwitcher.fadeOutDuration * _opacity.value,
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _direction = target > _shown ? 1 : -1;
      _shown = target;
    });
    _opacity.animateTo(
      1,
      duration: FadeThroughSwitcher.fadeInDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MotionAwareSize(
      duration: FadeThroughSwitcher.sizeDuration,
      child: AnimatedBuilder(
        animation: _opacity,
        builder: (context, child) {
          final v = _opacity.value;
          // Solo la sección entrante se desplaza; la saliente solo se apaga.
          final incoming = _shown == widget.index;
          final dx =
              incoming
                  ? _direction * FadeThroughSwitcher.slideDistance * (1 - v)
                  : 0.0;
          return Opacity(
            opacity: v,
            child: Transform.translate(offset: Offset(dx, 0), child: child),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.builders.length; i++)
              if (_built.contains(i))
                Offstage(
                  key: ValueKey(i),
                  offstage: i != _shown,
                  child: TickerMode(
                    enabled: i == _shown,
                    child: Builder(builder: widget.builders[i]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

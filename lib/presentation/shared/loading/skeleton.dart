import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Tiempos y opacidades del pulso de los skeletons.
abstract final class SkeletonMotion {
  /// Medio ciclo del pulso (va y vuelve): muy lento, se nota que carga sin
  /// llamar la atención.
  static const pulse = Duration(milliseconds: 1600);

  /// Opacidad más baja del pulso; la más alta es 1.
  static const minOpacity = 0.6;
}

/// Raíz de un skeleton: un solo pulso de opacidad para todos sus bloques
/// (no uno por bloque), estático con reduce motion, y un único nodo de
/// accesibilidad con [semanticsLabel] ("Cargando") en lugar de las barras.
///
/// Los [SkeletonBlock] sin [SkeletonScope] arriba se dibujan quietos.
class SkeletonScope extends StatefulWidget {
  const SkeletonScope({
    super.key,
    required this.child,
    this.semanticsLabel,
    this.announce = true,
  });

  final Widget child;

  /// Por defecto, `'loading'.tr()`.
  final String? semanticsLabel;

  /// `false` para un skeleton chico dentro de algo que ya se anuncia (ej.
  /// el precio de un plan): no agrega su propio "Cargando".
  final bool announce;

  @override
  State<SkeletonScope> createState() => _SkeletonScopeState();
}

class _SkeletonScopeState extends State<SkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: SkeletonMotion.pulse,
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 1,
    end: SkeletonMotion.minOpacity,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOutSine));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skeleton = _SkeletonPulse(
      opacity: _opacity,
      child: ExcludeSemantics(child: widget.child),
    );
    if (!widget.announce) return skeleton;
    return Semantics(
      container: true,
      label: widget.semanticsLabel ?? 'loading'.tr(),
      child: skeleton,
    );
  }
}

class _SkeletonPulse extends InheritedWidget {
  const _SkeletonPulse({required this.opacity, required super.child});

  final Animation<double> opacity;

  @override
  bool updateShouldNotify(_SkeletonPulse oldWidget) =>
      opacity != oldWidget.opacity;
}

/// Un bloque gris redondeado en lugar de algo que todavía no está. Nunca
/// aparenta un dato: sin texto ni números. Color por defecto: Elevated Mist
/// (`surfaceElevated`).
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    this.height,
    this.radius = 6,
    this.color,
  });

  /// Línea de texto: alto 10, puntas redondas.
  const SkeletonBlock.line({super.key, this.width, this.color})
    : height = 10,
      radius = 5;

  /// Círculo de [size] (logo, avatar).
  const SkeletonBlock.circle({super.key, required double size, this.color})
    : width = size,
      height = size,
      radius = size / 2;

  /// `null`: todo el ancho disponible.
  final double? width;

  /// `null`: todo el alto disponible.
  final double? height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? context.customColors.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    final pulse =
        context.getInheritedWidgetOfExactType<_SkeletonPulse>()?.opacity;
    if (pulse == null) return block;
    return FadeTransition(opacity: pulse, child: block);
  }
}

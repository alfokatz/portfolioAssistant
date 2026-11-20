import 'package:flutter/material.dart';

/// Desvanece el borde superior de la lista en los primeros [extent] px, en
/// vez de cortar el contenido en seco contra el header. Es una máscara de
/// alpha (no un gradiente de color encima), así funciona sobre el halo de
/// `AppBackgroundGradient` en light y dark sin tener que igualar su color.
/// Entra de a poco con el scroll: con la lista arriba del todo no hay nada
/// debajo del header y el primer mensaje se ve entero.
class TopEdgeFade extends StatelessWidget {
  const TopEdgeFade({
    super.key,
    required this.controller,
    required this.extent,
    required this.child,
  });

  final ScrollController controller;
  final double extent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      child: child,
      builder: (context, child) {
        final scrolled =
            controller.hasClients
                ? (controller.position.pixels / extent).clamp(0.0, 1.0)
                : 0.0;
        // Se mantiene el ShaderMask montado aunque no haya fade, para no
        // cambiar la estructura del árbol (y remontar la lista) al scrollear.
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback:
              (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 1 - scrolled),
                  Colors.black,
                ],
                stops: [0, (extent / bounds.height).clamp(0.0, 1.0)],
              ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

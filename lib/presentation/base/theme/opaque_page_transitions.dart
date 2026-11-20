import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

/// Envuelve un [PageTransitionsBuilder] de plataforma para que cada ruta
/// pinte su propio fondo ([RouteBackground]) por debajo de su contenido.
///
/// Los Scaffold de la app son transparentes a propósito (dejan ver el halo
/// de `AppBackgroundGradient`). Con un único fondo pintado detrás del
/// Router, dos rutas superpuestas durante una transición se veían una a
/// través de la otra (la home asomaba debajo del detalle mientras entraba).
/// Pintando el fondo dentro de la ruta, cada pantalla es opaca mientras
/// anima y en reposo se ve igual que antes.
///
/// La animación es la de [inner] sin cambios: en iOS el slide de Cupertino
/// con swipe-back (y su sombra de borde nativa, ~1,5% de negro, que no
/// oscurece la pantalla de abajo); en Android la transición por defecto.
class OpaquePageTransitionsBuilder extends PageTransitionsBuilder {
  const OpaquePageTransitionsBuilder(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Duration get transitionDuration => inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      inner.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return inner.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      RouteBackground(child: child),
    );
  }
}

/// Fondo opaco de una ruta: el halo de [AppBackgroundGradient] (que termina
/// en el color de canvas, así que cubre todo) debajo de [child]. Una sola
/// capa por ruta, en su propio [RepaintBoundary]: mientras la ruta se
/// desliza el fondo se reusa rasterizado, no se repinta por frame.
class RouteBackground extends StatelessWidget {
  const RouteBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        const Positioned.fill(
          child: RepaintBoundary(child: AppBackgroundGradient()),
        ),
        child,
      ],
    );
  }
}

/// Android: el mismo movimiento que `FadeForwardsPageTransitionsBuilder`
/// (la transición por defecto de Flutter en Android, que la app usaba),
/// misma duración, curva y desplazamiento, pero como "fade through": la
/// pantalla saliente termina de apagarse antes de que aparezca la nueva.
/// La de Flutter las cruza (la nueva aparece mientras la vieja todavía se
/// ve), y eso es exactamente una pantalla vista a través de la otra. Entre
/// las dos queda el color de canvas.
///
/// Sin predictive back: la app no lo tiene activado en el manifest
/// (`enableOnBackInvokedCallback`), así que el builder por defecto ya caía
/// siempre en fade forwards.
class FadeThroughForwardsPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughForwardsPageTransitionsBuilder();

  static const _curve = Curves.easeInOutCubicEmphasized;

  /// Fracción de la transición en que la saliente termina de apagarse; la
  /// entrante aparece en el tramo siguiente, de igual largo.
  static const _handoff = 0.25;

  static final _enterSlide = Tween<Offset>(
    begin: const Offset(0.25, 0),
    end: Offset.zero,
  ).chain(CurveTween(curve: _curve));
  static final _enterFade = CurveTween(
    curve: const Interval(_handoff, _handoff * 2, curve: Curves.easeOutCubic),
  );
  static final _exitSlide = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(-0.25, 0),
  ).chain(CurveTween(curve: _curve));
  static final _exitFade = Tween<double>(begin: 1, end: 0).chain(
    CurveTween(curve: const Interval(0, _handoff, curve: Curves.easeOutCubic)),
  );

  @override
  Duration get transitionDuration => const Duration(milliseconds: 450);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: _exitFade.animate(secondaryAnimation),
      child: SlideTransition(
        position: _exitSlide.animate(secondaryAnimation),
        child: FadeTransition(
          opacity: _enterFade.animate(animation),
          child: SlideTransition(
            position: _enterSlide.animate(animation),
            child: child,
          ),
        ),
      ),
    );
  }
}

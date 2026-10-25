import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

/// Página para los cruces de "estado de la app" (login → onboarding →
/// home y de vuelta al cerrar sesión): en vez del slide de plataforma, un
/// fade through opaco. Primero el fondo de la app tapa a la pantalla
/// saliente; recién cuando la cubre por completo aparece el contenido de la
/// nueva. Nunca se ven dos pantallas a la vez, mismo criterio que
/// `OpaquePageTransitionsBuilder`.
///
/// Con algo pusheado encima (ej. el detalle de una posición sobre la home)
/// se comporta como un `MaterialPage`: el parallax de iOS y el fade de
/// Android de la ruta de abajo siguen igual.
class FadeThroughPage<T> extends Page<T> {
  const FadeThroughPage({
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    required this.child,
  });

  final Widget child;

  static const duration = Duration(milliseconds: 400);

  /// Fracción de la transición en que el fondo termina de tapar a la
  /// saliente; el contenido nuevo aparece en el resto.
  static const handoff = 0.45;

  @override
  Route<T> createRoute(BuildContext context) =>
      _FadeThroughPageRoute<T>(page: this);
}

class _FadeThroughPageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _FadeThroughPageRoute({required FadeThroughPage<T> page})
    : super(settings: page);

  FadeThroughPage<T> get _page => settings as FadeThroughPage<T>;

  static final _backgroundFade = CurveTween(
    curve: const Interval(
      0,
      FadeThroughPage.handoff,
      curve: Curves.easeOutCubic,
    ),
  );
  static final _contentFade = CurveTween(
    curve: const Interval(
      FadeThroughPage.handoff,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => true;

  @override
  bool get fullscreenDialog => false;

  @override
  Duration get transitionDuration => FadeThroughPage.duration;

  @override
  Duration get reverseTransitionDuration => FadeThroughPage.duration;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  /// La ruta saliente no se desliza mientras esta entra: solo la tapa el
  /// fondo. (Sin esto, el slide de Cupertino movería la pantalla de abajo.)
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // La entrada propia es el fade; cuando otra ruta entra encima, la
    // transición de plataforma (que además pinta el fondo opaco de la ruta,
    // ver RouteBackground) maneja la animación secundaria como siempre.
    final themed = super.buildTransitions(
      context,
      kAlwaysCompleteAnimation,
      secondaryAnimation,
      child,
    );
    // Con reduce motion la pantalla aparece entera de una. Se cambia la
    // animación y no el árbol: si el setting cambia con la ruta abierta, el
    // contenido no se remonta.
    if (MediaQuery.disableAnimationsOf(context)) {
      animation = kAlwaysCompleteAnimation;
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: _backgroundFade.animate(animation),
            child: const RepaintBoundary(child: AppBackgroundGradient()),
          ),
        ),
        FadeTransition(opacity: _contentFade.animate(animation), child: themed),
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// Entrada suave al activar una página; respeta [MediaQuery.disableAnimations].
class OnboardingPageEntrance extends StatelessWidget {
  const OnboardingPageEntrance({
    super.key,
    required this.pageIndex,
    required this.activePage,
    required this.child,
  });

  final int pageIndex;
  final int activePage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (activePage != pageIndex || reduceMotion) return child;

    return TweenAnimationBuilder<double>(
      key: ValueKey('onboarding-page-$pageIndex-$activePage'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: 0.4 + (0.6 * value),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Entrada escalonada para hijos de una página activa.
class OnboardingStaggeredEntrance extends StatelessWidget {
  const OnboardingStaggeredEntrance({
    super.key,
    required this.pageIndex,
    required this.activePage,
    required this.itemIndex,
    required this.child,
  });

  final int pageIndex;
  final int activePage;
  final int itemIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (activePage != pageIndex || reduceMotion) return child;

    return TweenAnimationBuilder<double>(
      key: ValueKey('onboarding-stagger-$pageIndex-$itemIndex-$activePage'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + (itemIndex * 60)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: 0.35 + (0.65 * value),
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

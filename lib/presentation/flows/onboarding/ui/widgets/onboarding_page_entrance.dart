import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

/// Anima el contenido cuando su página del [PageView] queda activa.
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
    if (activePage != pageIndex) return child;

    return FadeInUp(
      key: ValueKey('onboarding-page-$pageIndex-$activePage'),
      duration: const Duration(milliseconds: 480),
      from: 22,
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

/// Entrada escalonada para elementos dentro de una página de onboarding.
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
    if (activePage != pageIndex) return child;

    return FadeInUp(
      key: ValueKey('onboarding-stagger-$pageIndex-$itemIndex-$activePage'),
      delay: Duration(milliseconds: 70 * itemIndex),
      duration: const Duration(milliseconds: 420),
      from: 18,
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

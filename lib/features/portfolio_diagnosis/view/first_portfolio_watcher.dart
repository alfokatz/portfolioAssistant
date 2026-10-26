import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/nav/portfolio_diagnosis_router.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';

/// El momento en que la cartera pasa de vacía a tener posiciones (por
/// cualquier camino: a mano, archivo, eToro, el chat). Registra
/// `portfolio_loaded` y, si todavía no vio su primer diagnóstico, lo abre
/// apenas está en la Home sin nada encima (no en medio de una charla con
/// Porty ni arriba de la pantalla de resultado de una importación).
///
/// Vive en el shell: es el único que sabe qué pestaña está activa.
class FirstPortfolioWatcher extends ConsumerStatefulWidget {
  const FirstPortfolioWatcher({
    super.key,
    required this.isHome,
    required this.child,
  });

  /// La pestaña activa es la Home.
  final bool isHome;
  final Widget child;

  @override
  ConsumerState<FirstPortfolioWatcher> createState() =>
      _FirstPortfolioWatcherState();
}

class _FirstPortfolioWatcherState extends ConsumerState<FirstPortfolioWatcher> {
  bool _pending = false;

  /// Vacía "de verdad": ya cargó bien (no es la caché, la primera carga ni
  /// una carga fallida que dejó ceros).
  static bool _confirmedEmpty(HomeState? s) =>
      s != null &&
      s.summary != null &&
      s.summary!.valuations.isEmpty &&
      !s.loading &&
      !s.fromCache &&
      s.quoteError == null;

  void _onHome(HomeState? previous, HomeState next) {
    final count = next.summary?.valuations.length ?? 0;
    if (!_confirmedEmpty(previous) || count == 0) return;
    final method = ref.read(portfolioLoadMethodProvider);
    ref.read(portfolioLoadMethodProvider.notifier).state = null;
    ref.read(productEventsProvider).log(ProductEvent.portfolioLoaded, {
      'method': method ?? PortfolioLoadMethod.manual,
      'count': count,
    });
    if (!ref.read(diagnosisSeenProvider)) setState(() => _pending = true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<HomeState>(homeProvider, _onHome);
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    if (_pending && widget.isHome && onTop) {
      _pending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ref.read(diagnosisSeenProvider)) return;
        context.pushNamed(PortfolioDiagnosisRouter.routeName);
      });
    }
    return widget.child;
  }
}

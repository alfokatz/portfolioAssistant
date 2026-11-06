import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_prompt_provider.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_add_sheet.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

/// Ofrece solo "Tené a Porty en tu pantalla de inicio" (ver
/// [WidgetPromptRules]). Vive en el shell, que es el único que sabe qué
/// pestaña está activa.
///
/// Para no apilar avisos: solo con la Home a la vista y sin ninguna hoja,
/// diálogo ni pantalla encima (`ModalRoute.isCurrent`, como el diagnóstico
/// de la primera cartera); espera [settleDelay] a que cierre lo que se haya
/// abierto con la app; una vez por apertura; y no en la apertura en la que
/// se acaba de ver el primer diagnóstico.
class WidgetPromptWatcher extends ConsumerStatefulWidget {
  const WidgetPromptWatcher({
    super.key,
    required this.isHome,
    required this.child,
    this.settleDelay = const Duration(seconds: 2),
  });

  final bool isHome;
  final Widget child;
  final Duration settleDelay;

  @override
  ConsumerState<WidgetPromptWatcher> createState() =>
      _WidgetPromptWatcherState();
}

class _WidgetPromptWatcherState extends ConsumerState<WidgetPromptWatcher> {
  Timer? _timer;

  /// Se vio el primer diagnóstico en esta apertura.
  bool _diagnosisThisOpen = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    // El shell se monta al iniciar sesión: lo guardado pudo cambiar.
    Future.microtask(() {
      if (mounted) ref.read(widgetPromptProvider.notifier).reload();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _hasPortfolio =>
      ref.read(homeProvider).summary?.valuations.isNotEmpty ?? false;

  bool get _onTop => ModalRoute.of(context)?.isCurrent ?? true;

  Future<void> _tryOffer() async {
    _timer = null;
    if (!mounted || _showing) return;
    final notifier = ref.read(widgetPromptProvider.notifier);
    if (_diagnosisThisOpen || !widget.isHome || !_onTop) return;
    // Barato primero: sin esto no vale la pena preguntarle al sistema.
    if (!notifier.shouldOffer(installed: false, hasPortfolio: _hasPortfolio)) {
      return;
    }
    List<String> sizes;
    try {
      sizes = await ref.read(homeWidgetStoreProvider).installedSizes();
    } catch (_) {
      return;
    }
    // Pasó tiempo: vuelve a mirar que nada se haya abierto encima.
    if (!mounted || !widget.isHome || !_onTop || _showing) return;
    if (!notifier.shouldOffer(
      installed: sizes.isNotEmpty,
      hasPortfolio: _hasPortfolio,
    )) {
      return;
    }
    _showing = true;
    await notifier.markShown();
    if (!mounted) return;
    await WidgetAddSheet.show(context, ref, source: WidgetPromptSource.auto);
    _showing = false;
  }

  @override
  Widget build(BuildContext context) {
    final prompt = ref.watch(widgetPromptProvider);
    final hasPortfolio = ref.watch(
      homeProvider.select((s) => s.summary?.valuations.isNotEmpty ?? false),
    );
    ref.listen<bool>(diagnosisSeenProvider, (previous, next) {
      if (previous == false && next) _diagnosisThisOpen = true;
    });
    ref.listen<int>(widgetPromptProvider.select((s) => s.opens), (_, __) {
      _diagnosisThisOpen = false;
    });
    final ready =
        widget.isHome &&
        hasPortfolio &&
        !_showing &&
        WidgetPromptRules.shouldOffer(
          opens: prompt.opens,
          offersShown: prompt.offersShown,
          lastOfferAt: prompt.lastOfferAt,
          now: DateTime.now(),
          installed: false,
          hasPortfolio: true,
          offeredThisOpen: prompt.offeredThisOpen,
        );
    if (ready && _timer == null) {
      _timer = Timer(widget.settleDelay, _tryOffer);
    } else if (!ready) {
      _timer?.cancel();
      _timer = null;
    }
    return widget.child;
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_home_widgets.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/weekly_report/view/weekly_report_card.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/benchmark_comparison_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/benchmark_locked_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/closed_positions_entry_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_empty_state.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_section_tabs.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_skeleton.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/pnl_distribution_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_hero_section.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_qa_entry_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/positions_section.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_through_switcher.dart';

class HomeScreen extends StatefulHookConsumerWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _HomeScreenState();
}

class _HomeScreenState extends BaseStatefulWidget<HomeScreen> {
  // Home stays mounted alongside Assistant and Settings inside the shell's
  // IndexedStack — AppShell is the single place that subscribes to
  // alerts/navigation events for all three tabs (see its docs).
  @override
  bool get subscribesToGlobalEvents => false;

  /// Sin nada guardado, el contenido entra escalonado al salir del
  /// skeleton; con caché ya está en pantalla desde el primer frame.
  late final bool _animateEntrance = ref.read(homeProvider).summary == null;

  Widget _enter(int order, Widget child) => FadeSlideIn(
    delay: Duration(milliseconds: 40 * order),
    skipAnimation: !_animateEntrance,
    child: child,
  );

  /// Pull-to-refresh en curso: la recarga de la Home la hace él (y no el
  /// listener de eToro), así el indicador espera a los datos nuevos.
  bool _pullRefreshing = false;

  @override
  void initState() {
    runAfterPostFrameCallback(() {
      ref.read(homeProvider.notifier).init();
    });
    super.initState();
  }

  /// Pull-to-refresh: primero eToro (si está conectada; el servidor limita
  /// a una sincronización cada 5 min), después la Home con lo que haya.
  Future<void> _onPullToRefresh() async {
    _pullRefreshing = true;
    try {
      await ref
          .read(etoroConnectionProvider.notifier)
          .sync(userInitiated: true);
      await ref.read(homeProvider.notifier).refresh();
    } finally {
      _pullRefreshing = false;
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final colors = context.customColors;
    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);
    final subscription = ref.watch(subscriptionProvider);
    final summary = state.summary;
    final etoro = ref.watch(etoroConnectionProvider);
    // Lo importado cambió (sincronización, conexión, desconexión): recargar
    // en el lugar, sin skeleton.
    ref.listen<int>(etoroConnectionProvider.select((s) => s.importRevision), (
      previous,
      next,
    ) {
      if (previous != null && previous != next && !_pullRefreshing) {
        notifier.refresh(silent: true);
      }
    });
    final isBenchmarkAllowed = SubscriptionPolicy.isBenchmarkAllowed(
      subscription.tier,
    );

    final filteredHistory = HomeChartUtils.filterHistory(
      state.history,
      state.selectedRange,
    );
    final filteredBenchmark = HomeChartUtils.filterBenchmark(
      state.benchmark,
      state.selectedRange,
    );
    final periodPnl =
        state.selectedRange == ChartTimeRange.all && summary != null
            ? PeriodPnl(
              absolute: summary.totalPnlAbsolute,
              percent: summary.totalPnlPercent,
            )
            : HomeChartUtils.periodPnlFromHistory(filteredHistory);

    final valuations = List<PositionValuation>.from(
      summary?.valuations ?? const [],
    )..sort((a, b) => b.pnlAbsolute.compareTo(a.pnlAbsolute));
    final hasMorePositions = valuations.length > 5;
    final displayValuations =
        state.showAllPositions
            ? valuations
            : valuations.take(5).toList(growable: false);

    final content = RefreshIndicator(
      color: colors.accentBlue,
      backgroundColor: colors.surfaceCard,
      onRefresh: _onPullToRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                //const HomeAppBar(),
                if (etoro.connection.needsReconnect)
                  const EtoroReconnectBanner(),
                if (state.quoteError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.pageHorizontal,
                      0,
                      AppDimens.pageHorizontal,
                      AppDimens.sp8,
                    ),
                    child: Material(
                      color: colors.surfaceCard,
                      borderRadius: BorderRadius.circular(
                        AppDimens.radiusLg,
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          state.quoteError!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                        trailing: TextButton(
                          onPressed: notifier.refresh,
                          child: Text('retry'.tr()),
                        ),
                      ),
                    ),
                  ),
                if (summary != null) ...[
                  _enter(
                    0,
                    PortfolioHeroSection(
                      summary: summary,
                      history: filteredHistory,
                      periodPnlAbsolute: periodPnl.absolute,
                      periodPnlPercent: periodPnl.percent,
                      selectedRange: state.selectedRange,
                      onRangeSelected: notifier.selectTimeRange,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sectionGap),
                  // Informe semanal de Porty (se oculta solo sin
                  // posiciones). Trae su propio espacio inferior.
                  _enter(
                    1,
                    WeeklyReportCard(
                      lots: [for (final lot in summary.lots) lot.position],
                    ),
                  ),
                  _enter(
                    2,
                    _HomeSections(
                      assets:
                          (_) =>
                              // Primera importación de eToro en curso: las
                              // filas en skeleton, no "no tenés posiciones".
                              valuations.isEmpty &&
                                      (etoro.isSyncing ||
                                          etoro.activity ==
                                              EtoroActivity.connecting)
                                  ? const SkeletonScope(
                                    child: PositionsSection.skeleton(rows: 3),
                                  )
                                  : PositionsSection(
                                    showConnectEtoro:
                                        etoro.loaded &&
                                        etoro.connection.status ==
                                            EtoroConnectionStatus.notConnected,
                                    valuations: displayValuations,
                                    totalCount: valuations.length,
                                    expanded: state.showAllPositions,
                                    onToggleExpanded:
                                        hasMorePositions
                                            ? notifier.togglePositionsExpanded
                                            : null,
                                    onPositionTap: notifier.openPositionDetail,
                                    onDeletePosition:
                                        (valuation) =>
                                            notifier.deletePositionsForTicker(
                                              valuation.position.ticker,
                                            ),
                                  ),
                      insights:
                          (_) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              PortfolioQaEntryCard(
                                onOpen: notifier.openAssistant,
                                onAsk:
                                    (question) => notifier.openAssistant(
                                      initialQuestion: question,
                                    ),
                                suggestions: _portySuggestions(valuations),
                              ),
                              if (isBenchmarkAllowed)
                                BenchmarkComparisonCard(
                                  portfolioPercent: periodPnl.percent,
                                  benchmarkPoints: filteredBenchmark,
                                  range: state.selectedRange,
                                )
                              else
                                const BenchmarkLockedCard(),
                              if (valuations.isNotEmpty)
                                PnlDistributionCard(valuations: valuations),
                              // Al final: es historial, no el estado actual
                              // de la cartera.
                              ClosedPositionsEntryCard(
                                count: state.closedPositionsCount,
                                onTap: notifier.openClosedPositions,
                              ),
                            ],
                          ),
                    ),
                  ),
                  const SizedBox(height: 100),
                ] else
                  HomeEmptyState(onAddPosition: notifier.openAddPosition),
              ],
            ),
          ),
        ],
      ),
    );

    // Nunca en blanco: sin nada que mostrar todavía, el skeleton (si la
    // carga pasa de 300 ms); con caché, los datos al instante.
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: LoadingSwitcher(
          loading: summary == null && state.loading,
          placeholder: (_) => const HomeSkeleton(),
          child: (_) => content,
        ),
      ),
    );
  }
}

/// Selector Activos / Insights + su contenido. El estado de la pestaña vive
/// acá y no en [HomeScreen]: antes, cada tap hacía `setState` en toda la
/// home (hero, gráfico, filtros de historia) solo para cambiar de pestaña.
/// Las dos pestañas quedan vivas en [FadeThroughSwitcher], así cambiar no
/// construye la de Insights (benchmark, distribución) en medio de la
/// animación.
class _HomeSections extends StatefulWidget {
  const _HomeSections({required this.assets, required this.insights});

  final WidgetBuilder assets;
  final WidgetBuilder insights;

  @override
  State<_HomeSections> createState() => _HomeSectionsState();
}

class _HomeSectionsState extends State<_HomeSections> {
  HomeSection _section = HomeSection.assets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionTabs(
          selected: _section,
          onSelected: (section) => setState(() => _section = section),
        ),
        const SizedBox(height: AppDimens.sp16),
        FadeThroughSwitcher(
          index: _section.index,
          builders: [widget.assets, widget.insights],
        ),
      ],
    );
  }
}

/// Preguntas listas para Porty en Insights. La del ticker sale de la
/// posición más grande de la cartera (dato real, nunca una lista fija).
List<String> _portySuggestions(List<PositionValuation> valuations) {
  final biggest =
      valuations.isEmpty
          ? null
          : valuations.reduce((a, b) => a.marketValue >= b.marketValue ? a : b);
  return [
    'home_porty_suggestion_week'.tr(),
    if (biggest != null)
      'home_porty_suggestion_ticker'.tr(
        namedArgs: {'ticker': biggest.position.ticker},
      ),
    'home_porty_suggestion_concentration'.tr(),
  ];
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';

/// Duplicados que el usuario ya marcó como "son distintas" (por ticker): no
/// se le vuelven a preguntar.
const etoroDismissedDuplicatesKey = 'etoro_dismissed_duplicates';

/// "Importamos N posiciones" y, aparte, lo que no se importó y por qué, en
/// lenguaje simple. Si alguna ya estaba cargada a mano, se pregunta qué
/// hacer (nunca se fusiona ni se borra solo).
class EtoroImportResultScreen extends StatefulHookConsumerWidget {
  const EtoroImportResultScreen({super.key, this.syncFailed = false});

  /// La cuenta quedó conectada pero la primera importación falló.
  final bool syncFailed;

  @override
  ConsumerState<EtoroImportResultScreen> createState() =>
      _EtoroImportResultScreenState();
}

class _EtoroImportResultScreenState
    extends BaseStatefulWidget<EtoroImportResultScreen> {
  @override
  bool get subscribesToGlobalEvents => false;

  late Set<String> _dismissed = _readDismissed();

  /// Tickers cuyas manuales se borraron en esta pantalla.
  final _resolved = <String>{};
  String? _deleting;

  Set<String> _readDismissed() {
    try {
      return ref
              .read(sharedPreferencesProvider)
              .getStringList(etoroDismissedDuplicatesKey)
              ?.toSet() ??
          <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _keepBoth(String ticker) async {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    setState(() => _dismissed = {..._dismissed, ticker});
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setStringList(etoroDismissedDuplicatesKey, _dismissed.toList());
    } catch (_) {}
  }

  Future<void> _deleteManual(String ticker) async {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    setState(() => _deleting = ticker);
    // Borra solo las cargadas a mano: las de eToro son de solo lectura.
    final ok = await ref
        .read(homeProvider.notifier)
        .deletePositionsForTicker(ticker);
    if (!mounted) return;
    setState(() {
      _deleting = null;
      if (ok) _resolved.add(ticker);
    });
  }

  void _goHome() {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    context.goNamed(HomeRouter.homeRouteName);
  }

  @override
  Widget buildView(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final state = ref.watch(etoroConnectionProvider);
    final result = state.connection.lastResult;
    final duplicates = [
      for (final t in result?.possibleDuplicates ?? const <String>[])
        if (!_dismissed.contains(t) && !_resolved.contains(t)) t,
    ];
    var order = 0;
    Widget enter(Widget child) => FadeSlideIn(
      delay: Duration(milliseconds: 60 * order++),
      child: child,
    );

    final imported = result?.imported ?? 0;
    final title =
        result == null
            ? 'etoro_result_pending_title'.tr()
            : imported == 0
            ? 'etoro_result_none_title'.tr()
            : imported == 1
            ? 'etoro_result_title_one'.tr()
            : 'etoro_result_title'.tr(namedArgs: {'count': '$imported'});
    final subtitle =
        result == null
            ? 'etoro_result_pending_body'.tr()
            : result.closedImported > 0
            ? 'etoro_result_subtitle_closed'.tr(
              namedArgs: {'count': '${result.closedImported}'},
            )
            : 'etoro_result_subtitle'.tr();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'etoro_close'.tr(),
            onPressed: _goHome,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.pageHorizontal,
                  0,
                  AppDimens.pageHorizontal,
                  AppDimens.sp24,
                ),
                children: [
                  enter(
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: tt.headlineMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp8),
                  enter(
                    Text(
                      subtitle,
                      style: tt.bodyLarge?.copyWith(
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (widget.syncFailed && result == null) ...[
                    const SizedBox(height: AppDimens.sp16),
                    Text(
                      'etoro_result_sync_failed'.tr(),
                      style: tt.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (state.isSyncing && result == null) ...[
                    const SizedBox(height: AppDimens.sectionGap),
                    const SkeletonScope(child: _GroupSkeleton()),
                  ],
                  MotionAwareSize(
                    duration: const Duration(milliseconds: 220),
                    child:
                        duplicates.isEmpty
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                              padding: const EdgeInsets.only(
                                top: AppDimens.sectionGap,
                              ),
                              child: _DuplicatesCard(
                                tickers: duplicates,
                                deleting: _deleting,
                                onDeleteManual: _deleteManual,
                                onKeepBoth: _keepBoth,
                              ),
                            ),
                  ),
                  if (result != null && result.notImported.isNotEmpty) ...[
                    const SizedBox(height: AppDimens.sectionGap),
                    enter(
                      _NotImportedSection(
                        title:
                            'etoro_result_not_imported_title'.tr(
                              namedArgs: {
                                'count': '${result.notImportedCount}',
                              },
                            ),
                        items: result.notImported,
                      ),
                    ),
                  ],
                  if (result != null && result.closedNotImported.isNotEmpty) ...[
                    const SizedBox(height: AppDimens.sectionGap),
                    enter(
                      _NotImportedSection(
                        title: 'etoro_result_closed_not_imported_title'.tr(),
                        items: result.closedNotImported,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                AppDimens.sp8,
                AppDimens.pageHorizontal,
                AppDimens.sp16,
              ),
              child: PositionPrimaryButton(
                label: 'etoro_result_cta'.tr(),
                onPressed: _goHome,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicatesCard extends StatelessWidget {
  const _DuplicatesCard({
    required this.tickers,
    required this.deleting,
    required this.onDeleteManual,
    required this.onKeepBoth,
  });

  final List<String> tickers;
  final String? deleting;
  final ValueChanged<String> onDeleteManual;
  final ValueChanged<String> onKeepBoth;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return _Section(
      title: 'etoro_result_duplicates_title'.tr(),
      body: 'etoro_result_duplicates_body'.tr(),
      children: [
        for (final ticker in tickers)
          Padding(
            padding: const EdgeInsets.only(top: AppDimens.sp12),
            // Ticker arriba y acciones abajo: con letra grande o textos
            // largos las acciones bajan de línea en vez de desbordar.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ticker,
                  style: tt.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppDimens.sp8,
                  children: [
                    TextButton(
                      onPressed:
                          deleting == null ? () => onKeepBoth(ticker) : null,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        minimumSize: const Size(
                          AppDimens.touchTarget,
                          AppDimens.touchTarget,
                        ),
                      ),
                      child: Text('etoro_result_duplicates_keep'.tr()),
                    ),
                    TextButton(
                      onPressed:
                          deleting == null
                              ? () => onDeleteManual(ticker)
                              : null,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        minimumSize: const Size(
                          AppDimens.touchTarget,
                          AppDimens.touchTarget,
                        ),
                        textStyle: tt.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(
                        deleting == ticker
                            ? 'etoro_result_duplicates_deleting'.tr()
                            : 'etoro_result_duplicates_delete'.tr(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Lo que no se importó, agrupado por motivo: título simple, explicación y
/// los tickers.
class _NotImportedSection extends StatelessWidget {
  const _NotImportedSection({required this.title, required this.items});

  final String title;
  final List<EtoroNotImportedItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final byReason = <EtoroSkipReason, List<EtoroNotImportedItem>>{};
    for (final item in items) {
      byReason.putIfAbsent(item.reason, () => []).add(item);
    }
    final groups = byReason.entries.toList();

    return _Section(
      title: title,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0)
            Divider(height: AppDimens.sp24, thickness: 1, color: colors.border)
          else
            const SizedBox(height: AppDimens.sp12),
          Semantics(
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'etoro_skip_title_${groups[i].key.name}'.tr(),
                  style: tt.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  groups[i].key.explanationKey.tr(),
                  style: tt.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppDimens.sp6),
                Text(
                  groups[i].value
                      .map(
                        (item) =>
                            item.count > 1
                                ? '${item.ticker} ×${item.count}'
                                : item.ticker,
                      )
                      .join(' · '),
                  style: tt.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.body, required this.children});

  final String title;
  final String? body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppDimens.cardPadding),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: tt.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: AppDimens.sp4),
            Text(
              body!,
              style: tt.bodySmall?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
          ...children,
        ],
      ),
    );
  }
}

class _GroupSkeleton extends StatelessWidget {
  const _GroupSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBlock.line(width: 180),
        SizedBox(height: AppDimens.sp12),
        SkeletonBlock.line(),
        SizedBox(height: AppDimens.sp8),
        SkeletonBlock.line(width: 240),
      ],
    );
  }
}

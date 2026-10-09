import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
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
                  AppDimens.sp8,
                  AppDimens.pageHorizontal,
                  AppDimens.sp24,
                ),
                children: [
                  enter(
                    Center(
                      child: EtoroPortyLockup(
                        state:
                            result == null
                                ? EtoroLinkState.idle
                                : EtoroLinkState.linked,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp24),
                  enter(
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: tt.displaySmall?.copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          height: 1.2,
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp8),
                  enter(
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: tt.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (widget.syncFailed && result == null) ...[
                    const SizedBox(height: AppDimens.sp16),
                    Text(
                      'etoro_result_sync_failed'.tr(),
                      textAlign: TextAlign.center,
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
    return _Section(
      icon: Icons.copy_all_rounded,
      title: 'etoro_result_duplicates_title'.tr(),
      body: 'etoro_result_duplicates_body'.tr(),
      children: [
        for (final (i, ticker) in tickers.indexed) ...[
          if (i > 0)
            Divider(height: AppDimens.sp32, thickness: 1, color: colors.border)
          else
            const SizedBox(height: AppDimens.sp16),
          _DuplicateRow(
            ticker: ticker,
            deleting: deleting,
            onDeleteManual: () => onDeleteManual(ticker),
            onKeepBoth: () => onKeepBoth(ticker),
          ),
        ],
      ],
    );
  }
}

/// Un ticker repetido: el ticker y qué pasa ("En eToro y cargada a mano"),
/// y abajo las dos salidas del mismo tamaño. Borrar es la tonal roja; con
/// letra grande los botones se apilan.
class _DuplicateRow extends StatelessWidget {
  const _DuplicateRow({
    required this.ticker,
    required this.deleting,
    required this.onDeleteManual,
    required this.onKeepBoth,
  });

  final String ticker;
  final String? deleting;
  final VoidCallback onDeleteManual;
  final VoidCallback onKeepBoth;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final busy = deleting != null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
    );
    final label = tt.labelLarge?.copyWith(fontWeight: FontWeight.w600);
    const padding = EdgeInsets.symmetric(
      horizontal: AppDimens.sp12,
      vertical: AppDimens.sp8,
    );

    final keep = OutlinedButton(
      onPressed: busy ? null : onKeepBoth,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.border),
        minimumSize: const Size(0, AppDimens.touchTarget),
        padding: padding,
        shape: shape,
        textStyle: label,
      ),
      child: Text(
        'etoro_result_duplicates_keep'.tr(),
        textAlign: TextAlign.center,
      ),
    );
    final delete = FilledButton(
      onPressed: busy ? null : onDeleteManual,
      style: FilledButton.styleFrom(
        backgroundColor: colors.lossContainer,
        foregroundColor: colors.loss,
        disabledBackgroundColor: colors.lossContainer.withValues(alpha: 0.6),
        disabledForegroundColor: colors.loss.withValues(alpha: 0.6),
        elevation: 0,
        minimumSize: const Size(0, AppDimens.touchTarget),
        padding: padding,
        shape: shape,
        textStyle: label,
      ),
      child: Text(
        deleting == ticker
            ? 'etoro_result_duplicates_deleting'.tr()
            : 'etoro_result_duplicates_delete'.tr(),
        textAlign: TextAlign.center,
      ),
    );
    final stack = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _TickerChip(
                label: ticker,
                style: tt.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppDimens.sp8),
              Expanded(
                child: Text(
                  'etoro_result_duplicates_row'.tr(),
                  style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp12),
          if (stack) ...[
            delete,
            const SizedBox(height: AppDimens.sp8),
            keep,
          ] else
            Row(
              children: [
                Expanded(child: keep),
                const SizedBox(width: AppDimens.sp8),
                Expanded(child: delete),
              ],
            ),
        ],
      ),
    );
  }
}

/// Lo que no se importó, agrupado por motivo: título simple, explicación y
/// los tickers en chips.
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
    final chipStyle = tt.labelLarge?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return _Section(
      icon: Icons.visibility_off_outlined,
      title: title,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0)
            Divider(height: AppDimens.sp32, thickness: 1, color: colors.border)
          else
            const SizedBox(height: AppDimens.sp16),
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
                const SizedBox(height: AppDimens.sp8),
                Wrap(
                  spacing: AppDimens.sp6,
                  runSpacing: AppDimens.sp6,
                  children: [
                    for (final item in groups[i].value)
                      _TickerChip(
                        label:
                            item.count > 1
                                ? '${item.ticker} ×${item.count}'
                                : item.ticker,
                        style: chipStyle,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Un ticker en una pastilla gris, como las marcas chicas de la app.
class _TickerChip extends StatelessWidget {
  const _TickerChip({required this.label, required this.style});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp8,
        vertical: AppDimens.sp4,
      ),
      decoration: BoxDecoration(
        color: context.customColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Text(label, style: style),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    this.body,
    required this.children,
  });

  final IconData icon;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // El ícono en un círculo teñido de acento, como en Ajustes.
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.accentBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: colors.accentBlue),
              ),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppDimens.sp6),
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
                  ],
                ),
              ),
            ],
          ),
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

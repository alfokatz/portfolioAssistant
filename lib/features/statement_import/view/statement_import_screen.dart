import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';
import 'package:portfolio_assistant/features/statement_import/providers/statement_import_provider.dart';
import 'package:portfolio_assistant/features/statement_import/view/import_row_edit_sheet.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Importar posiciones desde un CSV o PDF del bróker: elegir el archivo,
/// revisar la vista previa (cada fila se corrige o se descarta) e
/// importarlas como manuales.
class StatementImportScreen extends ConsumerWidget {
  const StatementImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(statementImportProvider);
    final notifier = ref.read(statementImportProvider.notifier);

    final Widget body = switch (state.phase) {
      ImportPhase.intro => _Intro(
        errorType: state.errorType,
        onPick: notifier.pickAndRead,
      ),
      ImportPhase.reading => const _Reading(),
      ImportPhase.preview || ImportPhase.importing => _Preview(state: state),
      ImportPhase.done => _Done(
        imported: state.importedCount,
        failed: state.failedTickers,
        onAnother: notifier.reset,
      ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('import_title'.tr()),
        leading: IconButton(
          tooltip: 'import_close'.tr(),
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed(HomeRouter.homeRouteName);
            }
          },
        ),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
          // Importando sigue siendo la vista previa (con el botón cargando).
          child: KeyedSubtree(
            key: ValueKey(
              state.phase == ImportPhase.importing
                  ? ImportPhase.preview
                  : state.phase,
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Mensaje simple para un error tipado del servidor (nunca el código).
String importErrorMessage(String type) => switch (type) {
  'file_too_large' => 'import_error_too_large'.tr(),
  'unsupported_type' => 'import_error_unsupported'.tr(),
  'nothing_found' => 'import_error_nothing_found'.tr(),
  'quota_exceeded' || 'daily_quota_exceeded' => 'import_error_quota'.tr(),
  'rate_limited' => 'import_error_rate_limited'.tr(),
  'network' => 'import_error_network'.tr(),
  'picker_failed' => 'import_error_picker'.tr(),
  _ => 'import_error_unavailable'.tr(),
};

class _Intro extends ConsumerWidget {
  const _Intro({required this.errorType, required this.onPick});

  final String? errorType;
  final Future<void> Function() onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final error = errorType;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp16,
        AppDimens.pageHorizontal,
        AppDimens.sp24,
      ),
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          child: Icon(
            Icons.upload_file_rounded,
            size: 28,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimens.sp20),
        Semantics(
          header: true,
          child: Text(
            'import_intro_title'.tr(),
            style: tt.headlineSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          'import_intro_body'.tr(),
          style: tt.bodyLarge?.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppDimens.sp20),
        for (final key in const [
          'import_intro_point_csv',
          'import_intro_point_pdf',
          'import_intro_point_review',
          'import_intro_point_privacy',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimens.sp12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_rounded,
                    size: AppDimens.iconMd,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Text(
                    key.tr(),
                    style: tt.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: AppDimens.sp8),
          Semantics(
            liveRegion: true,
            child: _Notice(
              icon: Icons.error_outline_rounded,
              text: importErrorMessage(error),
            ),
          ),
          if (error == 'quota_exceeded' || error == 'daily_quota_exceeded')
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.sp8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed:
                      () => SubscriptionPaywallSheet.show(
                        context,
                        ref,
                        reason: PaywallReason.quotaExceeded,
                      ),
                  child: Text('import_see_plans'.tr()),
                ),
              ),
            ),
        ],
        const SizedBox(height: AppDimens.sp24),
        PositionPrimaryButton(
          label: 'import_pick_file'.tr(),
          onPressed: () {
            PortyHapticsService.maybeOf(context)?.selectionTap();
            onPick();
          },
        ),
      ],
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.pageHorizontal),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppDimens.sp20),
              Text(
                'import_reading_title'.tr(),
                textAlign: TextAlign.center,
                style: tt.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppDimens.sp8),
              Text(
                'import_reading_body'.tr(),
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({required this.state});

  final StatementImportState state;

  String _warningText(ImportWarning w) => switch (w.type) {
    'skipped_rows' => 'import_warning_skipped'.tr(
      namedArgs: {'count': '${w.count ?? 0}'},
    ),
    'cash_skipped' => 'import_warning_cash'.tr(),
    'ambiguous_dates' => 'import_warning_dates'.tr(),
    'truncated' => 'import_warning_truncated'.tr(
      namedArgs: {'count': '${w.count ?? 0}'},
    ),
    'non_usd_currency' => 'import_warning_currency'.tr(
      namedArgs: {'currencies': w.currencies.join(', ')},
    ),
    _ => '',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final notifier = ref.read(statementImportProvider.notifier);
    final importing = state.phase == ImportPhase.importing;
    final ready = state.ready.length;
    final warnings = [
      for (final w in state.warnings)
        if (_warningText(w).isNotEmpty) _warningText(w),
    ];

    return Column(
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
              Semantics(
                header: true,
                child: Text(
                  state.rows.length == 1
                      ? 'import_preview_title_one'.tr()
                      : 'import_preview_title'.tr(
                        namedArgs: {'count': '${state.rows.length}'},
                      ),
                  style: tt.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.sp4),
              Text(
                state.source == ImportSource.ai
                    ? 'import_preview_subtitle_ai'.tr()
                    : 'import_preview_subtitle_csv'.tr(),
                style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              for (final w in warnings) ...[
                const SizedBox(height: AppDimens.sp12),
                _Notice(icon: Icons.info_outline_rounded, text: w),
              ],
              if (state.missingDates > 0 || state.missingPricesFillable > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppDimens.sp12),
                  child: Wrap(
                    spacing: AppDimens.sp8,
                    runSpacing: AppDimens.sp8,
                    children: [
                      if (state.missingDates > 0)
                        ActionChip(
                          avatar: const Icon(Icons.today_rounded, size: 18),
                          label: Text('import_fill_dates'.tr()),
                          onPressed: notifier.fillMissingDatesWithToday,
                        ),
                      if (state.missingPricesFillable > 0)
                        ActionChip(
                          avatar: const Icon(Icons.sell_outlined, size: 18),
                          label: Text('import_fill_prices'.tr()),
                          onPressed: notifier.fillMissingPricesWithCurrent,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: AppDimens.sp16),
              for (final row in state.rows)
                _RowTile(
                  row: row,
                  alreadyHeld: state.heldTickers.contains(row.ticker),
                  enabled: !importing,
                  onToggle: () => notifier.toggle(row.id),
                  onEdit:
                      () => ImportRowEditSheet.show(
                        context,
                        row: row,
                        onSave:
                            (edit) => notifier.updateRow(
                              row.id,
                              ticker: edit.ticker,
                              quantity: edit.quantity,
                              purchasePrice: edit.purchasePrice,
                              purchaseDate: edit.purchaseDate,
                            ),
                      ),
                ),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.exceedsLimit) ...[
                _Notice(
                  icon: Icons.lock_outline_rounded,
                  text: 'import_limit_exceeded'.tr(
                    namedArgs: {'limit': '${state.positionLimit}'},
                  ),
                  action: TextButton(
                    onPressed:
                        () => SubscriptionPaywallSheet.show(
                          context,
                          ref,
                          reason: PaywallReason.modeLocked,
                        ),
                    child: Text('import_see_plans'.tr()),
                  ),
                ),
                const SizedBox(height: AppDimens.sp12),
              ] else if (state.needsAttention > 0) ...[
                Text(
                  'import_needs_attention'.tr(
                    namedArgs: {'count': '${state.needsAttention}'},
                  ),
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppDimens.sp8),
              ],
              PositionPrimaryButton(
                label:
                    state.checkingQuotes
                        ? 'import_checking_tickers'.tr()
                        : ready == 1
                        ? 'import_cta_one'.tr()
                        : 'import_cta'.tr(namedArgs: {'count': '$ready'}),
                loading: importing,
                onPressed: state.canImport ? notifier.importReady : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.alreadyHeld,
    required this.enabled,
    required this.onToggle,
    required this.onEdit,
  });

  final ImportRow row;
  final bool alreadyHeld;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  /// Lo primero que le falta (o la aclaración más útil), en una línea.
  String? _note() {
    final issues = row.issues;
    if (issues.contains(ImportIssue.unknownTicker)) {
      return 'import_issue_ticker'.tr();
    }
    if (issues.contains(ImportIssue.price)) return 'import_issue_price'.tr();
    if (issues.contains(ImportIssue.date)) return 'import_issue_date'.tr();
    if (issues.contains(ImportIssue.quantity)) {
      return 'import_issue_quantity'.tr();
    }
    return null;
  }

  String? _info() {
    if (row.hasForeignCurrency) {
      return 'import_info_currency'.tr(namedArgs: {'currency': row.currency!});
    }
    if (alreadyHeld) return 'import_info_held'.tr();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final note = row.included ? _note() : null;
    final info = row.included ? _info() : null;
    final details = [
      AppNumberFormat.shares(row.quantity),
      if (row.purchasePrice != null) AppNumberFormat.money(row.purchasePrice!),
      if (row.purchaseDate != null)
        DateFormat.yMMMd().format(row.purchaseDate!),
    ].join(' · ');
    final muted = !row.included;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp8),
      child: Material(
        color: colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onEdit : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.sp4,
              AppDimens.sp8,
              AppDimens.sp12,
              AppDimens.sp8,
            ),
            child: Row(
              children: [
                Checkbox(
                  value: row.included,
                  onChanged: enabled ? (_) => onToggle() : null,
                  semanticLabel: 'import_include_semantics'.tr(
                    namedArgs: {'ticker': row.ticker},
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            row.ticker,
                            style: tt.titleSmall?.copyWith(
                              color:
                                  muted
                                      ? colors.textSecondary
                                      : colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (row.name != null) ...[
                            const SizedBox(width: AppDimens.sp8),
                            Expanded(
                              child: Text(
                                row.name!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodySmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (note != null || info != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          note ?? info!,
                          style: tt.bodySmall?.copyWith(
                            color:
                                note != null
                                    ? colors.accentWarm
                                    : colors.textSecondary,
                            fontWeight:
                                note != null
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (row.included && row.quote == QuoteCheck.pending)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.textSecondary,
                    ),
                  )
                else
                  Icon(
                    Icons.edit_outlined,
                    size: AppDimens.iconMd,
                    color: colors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({
    required this.imported,
    required this.failed,
    required this.onAnother,
  });

  final int imported;
  final List<String> failed;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp32,
        AppDimens.pageHorizontal,
        AppDimens.sp24,
      ),
      children: [
        Icon(
          imported > 0
              ? Icons.check_circle_outline_rounded
              : Icons.error_outline_rounded,
          size: 48,
          color: imported > 0 ? colors.profit : colors.textSecondary,
        ),
        const SizedBox(height: AppDimens.sp16),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            imported == 0
                ? 'import_done_none'.tr()
                : imported == 1
                ? 'import_done_title_one'.tr()
                : 'import_done_title'.tr(namedArgs: {'count': '$imported'}),
            textAlign: TextAlign.center,
            style: tt.headlineSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          'import_done_body'.tr(),
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        if (failed.isNotEmpty) ...[
          const SizedBox(height: AppDimens.sp16),
          _Notice(
            icon: Icons.error_outline_rounded,
            text: 'import_done_failed'.tr(
              namedArgs: {'tickers': failed.toSet().join(', ')},
            ),
          ),
        ],
        const SizedBox(height: AppDimens.sp32),
        PositionPrimaryButton(
          label: 'import_done_cta'.tr(),
          onPressed: () => context.goNamed(HomeRouter.homeRouteName),
        ),
        const SizedBox(height: AppDimens.sp8),
        TextButton(onPressed: onAnother, child: Text('import_another'.tr())),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppDimens.sp12),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppDimens.iconMd, color: colors.textSecondary),
          const SizedBox(width: AppDimens.sp8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: tt.bodySmall?.copyWith(
                    color: colors.textPrimary,
                    height: 1.4,
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

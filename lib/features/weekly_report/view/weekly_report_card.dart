import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report.dart';
import 'package:portfolio_assistant/features/weekly_report/nav/weekly_report_router.dart';
import 'package:portfolio_assistant/features/weekly_report/providers/weekly_report_controller.dart';
import 'package:portfolio_assistant/features/weekly_report/view/weekly_report_format.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

/// "Tu semana, por Porty" en la Home, entre el hero y las pestañas: el
/// titular de la semana y tres cifras. Lleva a la pantalla del informe.
///
/// Mientras se calcula (o Porty escribe) muestra la misma estructura con el
/// texto en skeleton, del alto final: al llegar los datos no se mueve nada.
class WeeklyReportCard extends ConsumerStatefulWidget {
  const WeeklyReportCard({super.key, required this.lots});

  /// Las compras de la cartera (de `PortfolioSummary.lots`).
  final List<Position> lots;

  static const switchDuration = Duration(milliseconds: 220);

  @override
  ConsumerState<WeeklyReportCard> createState() => _WeeklyReportCardState();
}

class _WeeklyReportCardState extends ConsumerState<WeeklyReportCard> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(WeeklyReportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lots, widget.lots)) _ensure();
  }

  /// Después del frame: un provider no se modifica en medio de un build.
  void _ensure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(weeklyReportControllerProvider.notifier).ensureFor(widget.lots);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<WeeklyReportState>(weeklyReportControllerProvider, (prev, next) {
      // Porty terminó de escribir mientras la Home está en pantalla.
      if (next.freshlyGenerated && !(prev?.freshlyGenerated ?? false)) {
        PortyHapticsService.maybeOf(context)?.textAnswerRevealed();
      }
    });
    final state = ref.watch(weeklyReportControllerProvider);
    if (state.status == WeeklyReportStatus.hidden) {
      return const SizedBox.shrink();
    }
    final report =
        state.status == WeeklyReportStatus.ready ? state.report : null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sectionGap,
      ),
      child: MotionAwareSize(
        duration: WeeklyReportCard.switchDuration,
        child: AnimatedSwitcher(
          duration:
              reduceMotion ? Duration.zero : WeeklyReportCard.switchDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          layoutBuilder:
              (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
          child:
              report == null
                  ? _CardBody(
                    key: const ValueKey('loading'),
                    report: null,
                    generating: state.generating,
                  )
                  : _CardBody(
                    key: ValueKey(
                      'ready-${report.week.key}-${report.variant.name}',
                    ),
                    report: report,
                    generating: false,
                  ),
        ),
      ),
    );
  }
}

class _CardBody extends ConsumerWidget {
  const _CardBody({super.key, required this.report, required this.generating});

  final WeeklyReport? report;
  final bool generating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final r = report;
    final benchmarkAllowed = ref.watch(weeklyReportBenchmarkAllowedProvider);
    final headlineStyle = tt.bodyLarge?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w500,
      height: 1.35,
      color: colors.textPrimary,
    );
    final top = r?.movers.firstOrNull;

    final body = Padding(
      padding: const EdgeInsets.all(AppDimens.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PortyAvatar(size: 28),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'weekly_report_title'.tr(),
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    SkeletonText(
                      r == null ? null : WeeklyReportFormat.range(context, r),
                      placeholder: '00 sept – 00 sept',
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Solo cuando se puede abrir.
              if (r != null)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: colors.textSecondary,
                ),
            ],
          ),
          const SizedBox(height: AppDimens.sp12),
          if (r == null && generating)
            Text(
              'weekly_report_preparing'.tr(),
              maxLines: 2,
              style: headlineStyle?.copyWith(color: colors.textSecondary),
            )
          else
            SkeletonText(
              r == null ? null : WeeklyReportFormat.headline(r),
              placeholder: 'Tu cartera tuvo una semana de movimientos',
              style: headlineStyle,
            ),
          const SizedBox(height: AppDimens.sp12),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'weekly_report_portfolio'.tr(),
                  value: r == null ? null : WeeklyReportFormat.pct(r.changePct),
                  valueColor: r == null ? null : colors.pnlColor(r.changePct),
                ),
              ),
              if (benchmarkAllowed && (r == null || r.vsSp500Pp != null))
                Expanded(
                  child: _Stat(
                    label: 'weekly_report_vs_sp500'.tr(),
                    value:
                        r == null ? null : WeeklyReportFormat.pts(r.vsSp500Pp!),
                    valueColor:
                        r == null ? null : colors.pnlColor(r.vsSp500Pp!),
                  ),
                ),
              Expanded(
                child: _Stat(
                  label: 'weekly_report_top_mover'.tr(),
                  value:
                      r == null
                          ? null
                          : top == null
                          ? '—'
                          : '${top.ticker} ${WeeklyReportFormat.pct(top.pricePct ?? 0)}',
                  valueColor:
                      top?.pricePct == null
                          ? null
                          : colors.pnlColor(top!.pricePct!),
                ),
              ),
            ],
          ),
          if (r?.variant == WeeklyReportVariant.numbersLocked) ...[
            const SizedBox(height: AppDimens.sp12),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: colors.textSecondary),
                const SizedBox(width: AppDimens.sp6),
                Expanded(
                  child: Text(
                    'weekly_report_locked_title'.tr(),
                    style: tt.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return Semantics(
      button: r != null,
      onTapHint: r == null ? null : 'weekly_report_open_hint'.tr(),
      child: Material(
        color: colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap:
              r == null
                  ? null
                  : () {
                    PortyHapticsService.maybeOf(context)?.selectionTap();
                    context.pushNamed(WeeklyReportRouter.routeName);
                  },
          child: body,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.valueColor});

  final String label;
  final String? value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.labelSmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppDimens.sp2),
        SkeletonText(
          value,
          placeholder: 'AAPL +0.0%',
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor ?? colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

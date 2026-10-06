import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/position_row_widget.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

/// "Mis posiciones" en la Home: una card como las de Insights, con título
/// fuerte, filas separadas solo por espacio y "Ver todas" al pie.
class PositionsSection extends StatelessWidget {
  /// Las filas que se muestran (todas, o las primeras si está colapsada).
  final List<PositionValuation> valuations;

  /// Cuántas posiciones hay en total (para el subtítulo y "Ver todas").
  final int? totalCount;

  /// Valor de toda la cartera, para el peso de cada posición.
  final double? portfolioValue;

  final bool expanded;

  /// Si es null no hay "Ver todas" (entran todas).
  final VoidCallback? onToggleExpanded;
  final void Function(PositionValuation valuation)? onPositionTap;
  final Future<bool> Function(PositionValuation valuation)? onDeletePosition;

  /// Filas de skeleton (ver [PositionsSection.skeleton]).
  final int _skeletonRows;

  const PositionsSection({
    super.key,
    required this.valuations,
    this.totalCount,
    this.portfolioValue,
    this.expanded = false,
    this.onToggleExpanded,
    this.onPositionTap,
    this.onDeletePosition,
  }) : _skeletonRows = 0;

  /// La misma card con [rows] filas en skeleton (para el skeleton de la
  /// Home: al llegar los datos no se mueve nada).
  const PositionsSection.skeleton({super.key, int rows = 5})
    : valuations = const [],
      totalCount = null,
      portfolioValue = null,
      expanded = false,
      onToggleExpanded = null,
      onPositionTap = null,
      onDeletePosition = null,
      _skeletonRows = rows;

  Future<bool> _confirmDelete(BuildContext context, String ticker) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('position_delete_title'.tr()),
        content: Text(
          'position_delete_message'.tr(namedArgs: {'ticker': ticker}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    // Los logos usan la paleta del kit de Porty.
    QaColors.resolve(Theme.of(context).brightness);
    final skeleton = _skeletonRows > 0;
    final count = totalCount ?? valuations.length;
    final subtitle =
        skeleton
            ? null
            : count == 1
            ? 'home_positions_count_one'.tr()
            : 'home_positions_count'.tr(namedArgs: {'count': '$count'});

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sp16,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: MotionAwareSize(
          duration: const Duration(milliseconds: 220),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.cardPadding,
                  AppDimens.cardPadding,
                  AppDimens.cardPadding,
                  AppDimens.sp8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'positions_my'.tr(),
                        style: tt.titleMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    SkeletonText(
                      subtitle,
                      placeholder: '0 posiciones',
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (skeleton)
                for (var i = 0; i < _skeletonRows; i++)
                  const PositionRowWidget.skeleton()
              else if (valuations.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppDimens.cardPadding),
                  child: Text(
                    'positions_empty'.tr(),
                    textAlign: TextAlign.center,
                    style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
                  ),
                )
              else
                for (final valuation in valuations)
                  _PositionDismissibleRow(
                    valuation: valuation,
                    portfolioValue: portfolioValue,
                    onPositionTap: onPositionTap,
                    onDeletePosition: onDeletePosition,
                    confirmDelete:
                        (ticker) => _confirmDelete(context, ticker),
                  ),
              if (onToggleExpanded != null)
                _ToggleButton(
                  expanded: expanded,
                  total: count,
                  onTap: onToggleExpanded!,
                )
              else
                const SizedBox(height: AppDimens.sp8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PositionDismissibleRow extends StatelessWidget {
  final PositionValuation valuation;
  final double? portfolioValue;
  final void Function(PositionValuation valuation)? onPositionTap;
  final Future<bool> Function(PositionValuation valuation)? onDeletePosition;
  final Future<bool> Function(String ticker) confirmDelete;

  const _PositionDismissibleRow({
    required this.valuation,
    required this.portfolioValue,
    required this.onPositionTap,
    required this.onDeletePosition,
    required this.confirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final row = PositionRowWidget(
      valuation: valuation,
      portfolioValue: portfolioValue,
      onDetailTap:
          onPositionTap == null ? null : () => onPositionTap!(valuation),
    );

    if (onDeletePosition == null) return row;

    return Dismissible(
      key: ValueKey(valuation.position.ticker),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final confirmed = await confirmDelete(valuation.position.ticker);
        if (!confirmed) return false;
        return onDeletePosition!(valuation);
      },
      background: Container(
        color: colors.loss.withValues(alpha: 0.85),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppDimens.cardPadding),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: row,
    );
  }
}

/// "Ver todas (7)" / "Ver menos", como en "P&L por activo".
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.expanded,
    required this.total,
    required this.onTap,
  });

  final bool expanded;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final label =
        expanded
            ? 'home_pnl_show_less'.tr()
            : 'home_pnl_show_all'.tr(args: ['$total']);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () {
          PortyHapticsService.maybeOf(context)?.selectionTap();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget + 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppDimens.sp4),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: AppDimens.iconMd,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

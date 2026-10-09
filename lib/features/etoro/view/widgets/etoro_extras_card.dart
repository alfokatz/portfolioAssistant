import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_sync_note.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';

/// "Además en eToro": lo que el usuario tiene en eToro y Porty no importa
/// como posición (cripto, CFD, fuera de EE.UU., apalancado, en corto) y el
/// efectivo disponible, con los valores que calcula eToro.
///
/// Va aparte a propósito (decisiones 3 y 4 de la investigación): no suma al
/// total de Porty ni al gráfico, porque Porty no cotiza esos activos. Así el
/// usuario ve todo lo que tiene sin que los números de Porty se mezclen con
/// los de eToro. Sin nada que mostrar, no ocupa lugar.
class EtoroExtrasCard extends ConsumerWidget {
  const EtoroExtrasCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(
      etoroConnectionProvider.select((s) => s.connection),
    );
    final result = connection.lastResult;
    if (!connection.hasImportedData || result == null || !result.hasExtras) {
      return const SizedBox.shrink();
    }
    return EtoroExtrasCardView(result: result, syncedAt: connection.lastSyncAt);
  }
}

/// La card con los datos ya resueltos (sin providers): la usan los tests.
class EtoroExtrasCardView extends StatefulWidget {
  const EtoroExtrasCardView({super.key, required this.result, this.syncedAt});

  final EtoroImportResult result;
  final DateTime? syncedAt;

  /// Filas visibles antes de "Ver más".
  static const collapsedRows = 4;

  @override
  State<EtoroExtrasCardView> createState() => _EtoroExtrasCardViewState();
}

class _EtoroExtrasCardViewState extends State<EtoroExtrasCardView> {
  bool _expanded = false;

  void _toggle() {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final result = widget.result;
    final holdings = result.otherHoldings;
    final hidden = holdings.length - EtoroExtrasCardView.collapsedRows;
    final visible =
        _expanded || hidden <= 0
            ? holdings
            : holdings.take(EtoroExtrasCardView.collapsedRows).toList();
    final cash = result.cashUsd;
    final syncedAt = widget.syncedAt ?? result.syncedAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sp16,
      ),
      child: Material(
        color: colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.cardPadding,
                  AppDimens.sp4,
                  AppDimens.cardPadding,
                  AppDimens.sp8,
                ),
                child: Row(
                  children: [
                    const EtoroAppIcon(size: 40),
                    const SizedBox(width: AppDimens.sp12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              'etoro_extras_title'.tr(),
                              style: tt.titleMedium?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            syncedAt == null
                                ? 'etoro_extras_subtitle'.tr()
                                : 'etoro_extras_subtitle_synced'.tr(
                                  namedArgs: {
                                    'time': EtoroSyncTime.relative(syncedAt),
                                  },
                                ),
                            style: tt.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (cash != null && cash > 0)
                _ExtrasRow(
                  leading: _CashIcon(size: _ExtrasRow.avatarSize),
                  title: 'etoro_extras_cash'.tr(),
                  subtitle: 'etoro_extras_cash_hint'.tr(),
                  value: AppNumberFormat.money(cash),
                ),
              MotionAwareSize(
                duration: const Duration(milliseconds: 220),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final h in visible)
                      _ExtrasRow(
                        leading: QaTickerAvatar(
                          ticker: h.ticker,
                          size: _ExtrasRow.avatarSize,
                        ),
                        title: h.ticker,
                        subtitle: _subtitle(h),
                        value: AppNumberFormat.money(h.valueUsd),
                        change:
                            h.pnlPercent == null
                                ? AppNumberFormat.signedMoney(h.pnlUsd)
                                : AppNumberFormat.percent(h.pnlPercent!),
                        changeColor: colors.pnlColor(h.pnlUsd),
                      ),
                  ],
                ),
              ),
              if (hidden > 0)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.sp8,
                    ),
                    child: TextButton(
                      onPressed: _toggle,
                      child: Text(
                        _expanded
                            ? 'etoro_extras_show_less'.tr()
                            : 'etoro_extras_show_more'.tr(
                              namedArgs: {'count': '$hidden'},
                            ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Bitcoin · Cripto": el nombre si eToro lo dio, y por qué está acá.
  static String _subtitle(EtoroOtherHolding h) {
    final kind = 'etoro_skip_title_${h.reason.name}'.tr();
    final name = h.name?.trim();
    return name == null || name.isEmpty || name == h.ticker
        ? kind
        : '$name · $kind';
  }
}

class _ExtrasRow extends StatelessWidget {
  const _ExtrasRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.value,
    this.change,
    this.changeColor,
  });

  static const avatarSize = 36.0;

  final Widget leading;
  final String title;
  final String subtitle;
  final String value;
  final String? change;
  final Color? changeColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    const tabular = [FontFeature.tabularFigures()];
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.cardPadding,
          vertical: AppDimens.sp8,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Row(
            children: [
              leading,
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.sp12),
              // Con letra grande en pantallas chicas los montos se achican
              // antes que desbordar (el nombre ya cede con elipsis).
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        value,
                        style: tt.titleSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          fontFeatures: tabular,
                        ),
                      ),
                      if (change != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          change!,
                          style: tt.bodySmall?.copyWith(
                            color: changeColor,
                            fontWeight: FontWeight.w600,
                            fontFeatures: tabular,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El efectivo con el mismo círculo teñido que los íconos de las cards.
class _CashIcon extends StatelessWidget {
  const _CashIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.textSecondary.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.account_balance_wallet_outlined,
        size: AppDimens.iconMd,
        color: colors.textSecondary,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Título grande: logo, ticker y nombre de la compañía. Al scrollear pasa a
/// la barra (ver `PositionDetailScreen`).
class PositionTickerHeader extends StatelessWidget {
  const PositionTickerHeader({super.key, required this.ticker});

  final String ticker;

  /// Scroll a partir del cual el título grande ya no se ve.
  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return QaBrandBuilder(
      ticker: ticker,
      builder:
          (context, brand) => Row(
            children: [
              QaTickerAvatar(ticker: ticker, brand: brand, size: 48),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        ticker,
                        style: tt.displaySmall?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                          height: 1.1,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (brand.name != null && brand.name!.isNotEmpty)
                      Text(
                        brand.name!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}

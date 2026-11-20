import 'package:flutter/material.dart';
import 'package:portfolio_assistant/config/env/app_env.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';

/// Pastilla "DEV" arriba a la derecha en los builds que no son de prod
/// (TestFlight contra la branch develop de Supabase). No intercepta toques
/// y en prod no ocupa nada.
class EnvBadge extends StatelessWidget {
  const EnvBadge({super.key, this.show});

  /// Para tests; por defecto, `!AppEnv.isProd`.
  final bool? show;

  @override
  Widget build(BuildContext context) {
    if (!(show ?? !AppEnv.isProd)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          left: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(
              top: AppDimens.sp4,
              right: AppDimens.sp12,
            ),
            // Por encima del Navigator no hay Material: sin esto el texto
            // hereda el estilo de error (subrayado amarillo).
            child: Material(
              type: MaterialType.transparency,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.sp6,
                    vertical: AppDimens.sp2,
                  ),
                  child: Text(
                    'DEV',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

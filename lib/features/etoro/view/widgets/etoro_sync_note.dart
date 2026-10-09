import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// "hace 5 min", "hace 2 h", "8 oct, 14:30" — localizado.
abstract final class EtoroSyncTime {
  static String relative(DateTime at, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(at);
    if (diff.inMinutes < 1) return 'etoro_synced_just_now'.tr();
    if (diff.inMinutes < 60) {
      return 'etoro_synced_minutes'.tr(
        namedArgs: {'count': '${diff.inMinutes}'},
      );
    }
    if (diff.inHours < 24) {
      return 'etoro_synced_hours'.tr(namedArgs: {'count': '${diff.inHours}'});
    }
    return DateFormat.MMMd().add_Hm().format(at);
  }
}

/// Fila plana (sin card): "Se actualiza desde eToro · Última sincronización:
/// hace 5 min". Va donde estarían las acciones de editar o cerrar, que una
/// posición importada no tiene.
class EtoroSyncNote extends StatelessWidget {
  const EtoroSyncNote({super.key, required this.syncedAt, this.partial = false});

  final DateTime? syncedAt;

  /// Solo algunas compras vienen de eToro (el resto es manual).
  final bool partial;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final syncedAt = this.syncedAt;
    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.sync_rounded,
              size: AppDimens.iconMd,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partial
                      ? 'etoro_detail_partial_note'.tr()
                      : 'etoro_detail_note'.tr(),
                  style: tt.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (syncedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'etoro_last_sync'.tr(
                      namedArgs: {'when': EtoroSyncTime.relative(syncedAt)},
                    ),
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

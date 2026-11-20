import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/manual_positions/data/manual_positions_repository.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

/// Recarga la Home después de borrar (se reemplaza en los tests).
final manualPositionsRefreshProvider = Provider<Future<void> Function()>(
  (ref) => () => ref.read(homeProvider.notifier).refresh(silent: true),
);

/// Al traer la cartera de un bróker, qué hacer con lo cargado a mano:
/// quedarse solo con lo importado (se borran las abiertas manuales) o
/// conservar las dos. Las ventas cargadas a mano no se tocan.
abstract final class ManualPositionsChoice {
  /// Si tiene acciones cargadas a mano, pregunta. `true` si las borró.
  static Future<bool> offer(
    BuildContext context,
    WidgetRef ref, {
    required String broker,
  }) async {
    final repo = ref.read(manualPositionsRepositoryProvider);
    final int count;
    try {
      count = await repo.countTickers();
    } on ManualPositionsException {
      return false;
    }
    if (count == 0 || !context.mounted) return false;
    final replace = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ChoiceSheet(broker: broker, count: count),
    );
    if (replace != true || !context.mounted) return false;
    try {
      await repo.deleteAll();
    } on ManualPositionsException {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'manual_positions_delete_failed'.tr());
      return false;
    }
    await ref.read(manualPositionsRefreshProvider)();
    ref
        .read(alertProvider.notifier)
        .showSuccess(
          message: 'manual_positions_deleted'.tr(namedArgs: {'broker': broker}),
        );
    return true;
  }
}

/// Fila plana para la pantalla de un bróker conectado: "Además tenés N
/// acciones cargadas a mano" y la acción que abre la misma pregunta. No
/// aparece si no tiene ninguna.
class ManualPositionsRow extends ConsumerStatefulWidget {
  const ManualPositionsRow({super.key, required this.broker});

  final String broker;

  @override
  ConsumerState<ManualPositionsRow> createState() => _ManualPositionsRowState();
}

class _ManualPositionsRowState extends ConsumerState<ManualPositionsRow> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final count =
          await ref.read(manualPositionsRepositoryProvider).countTickers();
      if (mounted) setState(() => _count = count);
    } on ManualPositionsException {
      // Sin dato no se ofrece nada.
    }
  }

  Future<void> _open() async {
    await ManualPositionsChoice.offer(context, ref, broker: widget.broker);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp12),
      child: Row(
        children: [
          Icon(
            Icons.edit_note_rounded,
            size: AppDimens.iconMd,
            color: colors.textSecondary,
          ),
          const SizedBox(width: AppDimens.sp8),
          Expanded(
            child: Text(
              (_count == 1
                      ? 'manual_positions_row_one'
                      : 'manual_positions_row_count')
                  .tr(namedArgs: {'count': '$_count'}),
              style: tt.bodySmall?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
          TextButton(
            onPressed: _open,
            style: TextButton.styleFrom(
              foregroundColor: colors.textPrimary,
              minimumSize: const Size(
                AppDimens.touchTarget,
                AppDimens.touchTarget,
              ),
            ),
            child: Text('manual_positions_row_cta'.tr()),
          ),
        ],
      ),
    );
  }
}

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({required this.broker, required this.count});

  final String broker;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'manual_positions_title'.tr(),
              style: tt.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              (count == 1
                      ? 'manual_positions_body_one'
                      : 'manual_positions_body_count')
                  .tr(namedArgs: {'count': '$count', 'broker': broker}),
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppDimens.sp20),
            PositionPrimaryButton(
              label: 'manual_positions_keep'.tr(),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: AppDimens.sp8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.loss,
                  side: BorderSide(color: colors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  ),
                ),
                child: Text(
                  'manual_positions_replace'.tr(namedArgs: {'broker': broker}),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

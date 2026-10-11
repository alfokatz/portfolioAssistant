import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/porty_outfit/domain/porty_outfit.dart';
import 'package:portfolio_assistant/features/porty_outfit/providers/porty_outfit_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Ajustes → "Personalizá a Porty": Porty grande con lo que tiene puesto y,
/// debajo, los accesorios por lugar (cabeza, cara, cuello). Tocar uno se lo
/// pone (reemplaza el de ese lugar) o se lo saca; se guarda en el acto.
class PortyOutfitScreen extends ConsumerStatefulWidget {
  const PortyOutfitScreen({super.key});

  @override
  ConsumerState<PortyOutfitScreen> createState() => _PortyOutfitScreenState();
}

class _PortyOutfitScreenState extends ConsumerState<PortyOutfitScreen> {
  /// Cambia en cada toque para que Porty festeje (saltito) el accesorio.
  var _celebrate = PortyAvatarState.idle;

  void _toggle(PortyAccessory accessory) {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    final wearing = ref.read(portyOutfitProvider).wears(accessory);
    ref.read(portyOutfitProvider.notifier).toggle(accessory);
    setState(
      () =>
          _celebrate =
              wearing ? PortyAvatarState.idle : PortyAvatarState.answered,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final outfit = ref.watch(portyOutfitProvider);

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (!outfit.isEmpty)
            TextButton(
              onPressed: () {
                ref.read(portyOutfitProvider.notifier).clear();
                setState(() => _celebrate = PortyAvatarState.idle);
              },
              child: Text(
                'porty_outfit_reset'.tr(),
                style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp32,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              'porty_outfit_title'.tr(),
              style: tt.displaySmall?.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp8),
          Text(
            'porty_outfit_body'.tr(),
            style: tt.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppDimens.sp24),
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: colors.surfaceCard,
                shape: BoxShape.circle,
                border: Border.all(color: colors.border),
              ),
              alignment: Alignment.center,
              child: ExcludeSemantics(
                child: PortyAvatar(
                  size: 150,
                  animated: true,
                  state: _celebrate,
                  outfit: outfit,
                  onTap: () {},
                ),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp24),
          for (final slot in PortyOutfitSlot.values) ...[
            Padding(
              padding: const EdgeInsets.only(
                left: AppDimens.sp4,
                bottom: AppDimens.sp8,
              ),
              child: Text(
                'porty_outfit_slot_${slot.name}'.tr().toUpperCase(),
                style: tt.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppDimens.sp8,
              crossAxisSpacing: AppDimens.sp8,
              childAspectRatio: 0.9,
              children: [
                for (final accessory in PortyAccessory.values)
                  if (accessory.slot == slot)
                    _AccessoryTile(
                      accessory: accessory,
                      selected: outfit.wears(accessory),
                      onTap: () => _toggle(accessory),
                    ),
              ],
            ),
            const SizedBox(height: AppDimens.sp20),
          ],
        ],
      ),
    );
  }
}

class _AccessoryTile extends StatelessWidget {
  const _AccessoryTile({
    required this.accessory,
    required this.selected,
    required this.onTap,
  });

  final PortyAccessory accessory;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final label = 'porty_outfit_item_${accessory.storageValue}'.tr();
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color:
            selected
                ? colors.accentBlue.withValues(alpha: 0.10)
                : colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(
            color: selected ? colors.accentBlue : colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.sp8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PortyAvatar(
                  size: 56,
                  outfit: PortyOutfit({accessory.slot: accessory}),
                ),
                const SizedBox(height: AppDimens.sp6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

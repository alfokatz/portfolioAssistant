import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Encabezado de la Home: la fecha y un saludo a la izquierda, y Porty a la
/// derecha (respira en reposo; tocarlo abre el chat). Compacto a propósito:
/// le da identidad a la pantalla sin quitarle el protagonismo al total.
/// Es el mismo con datos y en skeleton (no depende de la cartera), así que
/// al cargar no se mueve.
class HomeAppBar extends StatelessWidget {
  const HomeAppBar({super.key, required this.firstName, this.onOpenPorty});

  /// `null` saluda sin nombre.
  final String? firstName;

  /// `null` deja a Porty sin interacción (skeleton).
  final VoidCallback? onOpenPorty;

  static const avatarSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final textTheme = Theme.of(context).textTheme;
    // El idioma del `MaterialApp` (EasyLocalization lo fija ahí).
    final date = DateFormat.MMMMEEEEd(
      Localizations.maybeLocaleOf(context)?.toLanguageTag(),
    ).format(DateTime.now());
    final name = firstName;
    final onOpen = onOpenPorty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp8,
        AppDimens.pageHorizontal,
        AppDimens.sp16,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _capitalized(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelLarge?.copyWith(
                    color: colors.textSecondary,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: AppDimens.sp2),
                Semantics(
                  header: true,
                  child: Text(
                    name == null
                        ? 'home_greeting'.tr()
                        : 'home_greeting_name'.tr(namedArgs: {'name': name}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      height: 1.2,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDimens.sp12),
          Semantics(
            button: onOpen != null,
            label: 'home_open_porty'.tr(),
            excludeSemantics: true,
            child: PortyAvatar(
              size: avatarSize,
              animated: true,
              onTap:
                  onOpen == null
                      ? null
                      : () {
                        PortyHapticsService.maybeOf(context)?.selectionTap();
                        onOpen();
                      },
            ),
          ),
        ],
      ),
    );
  }

  static String _capitalized(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

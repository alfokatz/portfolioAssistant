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
  const HomeAppBar({
    super.key,
    required this.firstName,
    this.onOpenPorty,
    this.onOpenProfile,
    this.now,
  });

  /// `null` saluda sin nombre.
  final String? firstName;

  /// `null` deja a Porty sin interacción (skeleton).
  final VoidCallback? onOpenPorty;

  /// Con Noticias prendida Ajustes sale de la barra de pestañas: un botón
  /// redondo (la inicial o una persona) a la derecha de Porty. `null` lo
  /// oculta (la barra de siempre ya lleva Ajustes).
  final VoidCallback? onOpenProfile;

  static const avatarSize = 44.0;

  /// La hora del saludo (tests y screenshots); `null` es ahora.
  final DateTime? now;

  /// Porty saluda según la hora: "Buen día" hasta las 13, "Buenas tardes"
  /// hasta las 20, después "Buenas noches".
  static String greetingKey(DateTime time, {required bool withName}) {
    final part = switch (time.hour) {
      >= 5 && < 13 => 'morning',
      >= 13 && < 20 => 'afternoon',
      _ => 'night',
    };
    return withName ? 'home_greeting_${part}_name' : 'home_greeting_$part';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final textTheme = Theme.of(context).textTheme;
    // El idioma del `MaterialApp` (EasyLocalization lo fija ahí).
    final time = now ?? DateTime.now();
    final date = DateFormat.MMMMEEEEd(
      Localizations.maybeLocaleOf(context)?.toLanguageTag(),
    ).format(time);
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
                        ? greetingKey(time, withName: false).tr()
                        : greetingKey(
                          time,
                          withName: true,
                        ).tr(namedArgs: {'name': name}),
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
          if (onOpenProfile != null) ...[
            const SizedBox(width: AppDimens.sp8),
            Semantics(
              button: true,
              label: 'home_open_profile'.tr(),
              excludeSemantics: true,
              child: InkResponse(
                key: const Key('home_profile_button'),
                onTap: onOpenProfile,
                customBorder: const CircleBorder(),
                child: Container(
                  width: avatarSize,
                  height: avatarSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surfaceCard,
                    border: Border.all(color: colors.border),
                  ),
                  child:
                      name == null
                          ? Icon(
                            Icons.person_outline_rounded,
                            size: AppDimens.iconMd,
                            color: colors.textPrimary,
                          )
                          : Text(
                            name.characters.first.toUpperCase(),
                            style: textTheme.titleMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _capitalized(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_headline_row.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

/// Vacío o error: Porty lo dice en una frase y, si se puede, ofrece la
/// salida. Nunca una caja vacía.
class NewsMessage extends StatelessWidget {
  const NewsMessage({
    super.key,
    required this.messageKey,
    required this.text,
    this.failed = false,
    this.actionLabel,
    this.onAction,
    this.mood,
  });

  final String messageKey;
  final String text;
  final bool failed;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Por defecto `concerned` si [failed] y `idle` si no.
  final PortyAvatarState? mood;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PortySays(
            messageKey: messageKey,
            mood:
                mood ??
                (failed ? PortyAvatarState.concerned : PortyAvatarState.idle),
            message: Text(text, style: PortySays.style(context)),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppDimens.sp12),
            NewsHeadlineActions(readLabel: actionLabel, onRead: onAction),
          ],
        ],
      ),
    );
  }
}

/// Un título de sección, con la tipografía del brief.
class NewsSectionTitle extends StatelessWidget {
  const NewsSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.25,
        color: context.customColors.textPrimary,
      ),
    ),
  );
}

/// Aviso de IA y "no es una recomendación" al pie.
class NewsDisclaimer extends StatelessWidget {
  const NewsDisclaimer({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppDimens.sp24),
    child: Text(
      'news_ai_notice'.tr(),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: context.customColors.textSecondary,
      ),
    ),
  );
}

/// Separador entre bloques de una pantalla de noticias.
const newsBlockGap = SizedBox(height: 36);

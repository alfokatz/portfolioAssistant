import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Piezas comunes de los mockups del onboarding. Todo lo que se muestra es
/// una cartera inventada y así se presenta ([OnboardingSampleCaption]),
/// nunca como dato real del usuario. Nada sale a la red: los logos son
/// monogramas.
const onboardingTabular = [FontFeature.tabularFigures()];

/// Card base de los mockups: la misma superficie que las cards de la app.
class OnboardingMockCard extends StatelessWidget {
  const OnboardingMockCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

/// "Ejemplo": encima de cada mockup, para que nadie confunda los números
/// con los suyos.
class OnboardingSampleCaption extends StatelessWidget {
  const OnboardingSampleCaption({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Row(
      children: [
        Icon(Icons.visibility_outlined, size: 14, color: colors.textSecondary),
        const SizedBox(width: AppDimens.sp6),
        Flexible(
          child: Text(
            'onboarding_sample_caption'.tr(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Lo que incluye un plan ("Premium", "Gold"), para no prometer de más.
class OnboardingPlanTag extends StatelessWidget {
  const OnboardingPlanTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.accentBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.accentBlue,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Avatar con monograma, sin pedir el logo (el onboarding no sale a la red).
class OnboardingTickerAvatar extends StatelessWidget {
  const OnboardingTickerAvatar({
    super.key,
    required this.ticker,
    this.size = 28,
  });

  final String ticker;
  final double size;

  @override
  Widget build(BuildContext context) {
    QaColors.resolve(Theme.of(context).brightness);
    return QaTickerAvatar(
      ticker: ticker,
      size: size,
      brand: CompanyBrand(ticker: ticker),
    );
  }
}

/// El mensaje del usuario, como en el chat: burbuja a la derecha.
class OnboardingUserBubble extends StatelessWidget {
  const OnboardingUserBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: AppDimens.sp40),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.sp16,
          vertical: AppDimens.sp12,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        ),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
        ),
      ),
    );
  }
}

/// La respuesta de Porty, como en el chat: texto suelto al lado del avatar.
class OnboardingPortyReply extends StatelessWidget {
  const OnboardingPortyReply({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ExcludeSemantics(
          child: PortyAvatar(size: 32, state: PortyAvatarState.answered),
        ),
        const SizedBox(width: AppDimens.sp12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Algo que se le puede pedir a Porty, con la chispa de las preguntas
/// sugeridas de la app. No es un botón: en el onboarding todavía no hay
/// cartera con la que responder.
class OnboardingExamplePrompt extends StatelessWidget {
  const OnboardingExamplePrompt({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp16,
        vertical: AppDimens.sp12,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: PortySpark(size: 12, color: colors.accentBlue),
          ),
          const SizedBox(width: AppDimens.sp8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

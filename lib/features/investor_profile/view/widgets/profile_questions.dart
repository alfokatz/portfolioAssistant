import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/investor_profile/view/widgets/investor_profile_option_row.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Las respuestas del perfil mientras se completan o editan.
@immutable
class ProfileAnswers {
  const ProfileAnswers({
    this.risk,
    this.horizon,
    this.objective,
    this.experience,
    this.drawdown,
  });

  factory ProfileAnswers.of(InvestorProfile? profile) => ProfileAnswers(
    risk: profile?.risk,
    horizon: profile?.horizon,
    objective: profile?.objective,
    experience: profile?.experience,
    drawdown: profile?.drawdownReaction,
  );

  final RiskTolerance? risk;
  final InvestmentHorizon? horizon;
  final InvestmentObjective? objective;
  final InvestmentExperience? experience;
  final DrawdownReaction? drawdown;

  /// Las tres necesarias para guardar.
  bool get isComplete => risk != null && horizon != null && objective != null;
}

typedef ProfileOption = ({Object value, String label, String? description});

/// Las preguntas del perfil, en orden. Las dos últimas son opcionales.
enum ProfileQuestion {
  risk,
  horizon,
  objective,
  experience,
  drawdown;

  bool get isOptional => this == experience || this == drawdown;

  String get title => 'investor_profile_q_$name'.tr();

  /// Nombre corto de la fila del resumen ("Riesgo", "Horizonte"…).
  String get shortLabel => 'investor_profile_label_$name'.tr();

  List<ProfileOption> get options => switch (this) {
    risk => [
      for (final v in RiskTolerance.values)
        (
          value: v,
          label: 'investor_profile_risk_${v.storageValue}'.tr(),
          description: 'investor_profile_risk_${v.storageValue}_desc'.tr(),
        ),
    ],
    horizon => [
      for (final v in InvestmentHorizon.values)
        (
          value: v,
          label: 'investor_profile_horizon_${v.storageValue}'.tr(),
          description: 'investor_profile_horizon_${v.storageValue}_desc'.tr(),
        ),
    ],
    objective => [
      for (final v in InvestmentObjective.values)
        (
          value: v,
          label: 'investor_profile_objective_${v.storageValue}'.tr(),
          description:
              'investor_profile_objective_${v.storageValue}_desc'.tr(),
        ),
    ],
    experience => [
      for (final v in InvestmentExperience.values)
        (
          value: v,
          label: 'investor_profile_experience_${v.storageValue}'.tr(),
          description:
              'investor_profile_experience_${v.storageValue}_desc'.tr(),
        ),
    ],
    drawdown => [
      for (final v in DrawdownReaction.values)
        (
          value: v,
          label: 'investor_profile_drawdown_${v.storageValue}'.tr(),
          description: null,
        ),
    ],
  };

  Object? valueIn(ProfileAnswers a) => switch (this) {
    risk => a.risk,
    horizon => a.horizon,
    objective => a.objective,
    experience => a.experience,
    drawdown => a.drawdown,
  };

  /// [a] con esta respuesta cambiada (`null` = sin responder).
  ProfileAnswers answer(ProfileAnswers a, Object? value) => ProfileAnswers(
    risk: this == risk ? value as RiskTolerance? : a.risk,
    horizon: this == horizon ? value as InvestmentHorizon? : a.horizon,
    objective: this == objective ? value as InvestmentObjective? : a.objective,
    experience:
        this == experience ? value as InvestmentExperience? : a.experience,
    drawdown: this == drawdown ? value as DrawdownReaction? : a.drawdown,
  );

  /// La respuesta como se lee en el resumen, o `null` si no respondió.
  String? answerLabel(ProfileAnswers a) {
    final value = valueIn(a);
    if (value == null) return null;
    return options.firstWhere((o) => o.value == value).label;
  }
}

/// Una pregunta con Porty: su avatar arriba, la pregunta como si la dijera
/// él y las respuestas como filas de una card. Se usa en el carrusel de la
/// primera vez y al editar una sola respuesta desde el resumen.
class ProfileQuestionView extends StatelessWidget {
  const ProfileQuestionView({
    super.key,
    required this.question,
    required this.selected,
    required this.onSelected,
    this.eyebrow,
    this.intro,
  });

  final ProfileQuestion question;
  final Object? selected;
  final ValueChanged<Object> onSelected;

  /// "Pregunta 2 de 5" (en el carrusel).
  final String? eyebrow;

  /// Una línea de Porty antes de la pregunta (solo la primera vez).
  final String? intro;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final eyebrow = this.eyebrow;
    final intro = this.intro;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp8,
        AppDimens.pageHorizontal,
        AppDimens.sp24,
      ),
      children: [
        if (eyebrow != null || question.isOptional) ...[
          Row(
            children: [
              if (eyebrow != null)
                Expanded(
                  child: Text(
                    eyebrow.toUpperCase(),
                    style: tt.labelSmall?.copyWith(
                      color: colors.accentBlue,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                )
              else
                const Spacer(),
              if (question.isOptional) ...[
                const SizedBox(width: AppDimens.sp8),
                Flexible(child: _OptionalTag()),
              ],
            ],
          ),
          const SizedBox(height: AppDimens.sp16),
        ],
        // Porty es quien pregunta: su avatar y, al lado, lo que dice.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: PortyAvatar(size: 56, animated: true),
            ),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (intro != null) ...[
                    Text(
                      intro,
                      style: tt.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppDimens.sp6),
                  ],
                  Semantics(
                    header: true,
                    child: Text(
                      question.title,
                      style: tt.displaySmall?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        height: 1.25,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.sp24),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              for (final (i, option) in question.options.indexed) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppDimens.cardPadding,
                    endIndent: AppDimens.cardPadding,
                    color: colors.border,
                  ),
                InvestorProfileOptionRow(
                  label: option.label,
                  description: option.description,
                  isSelected: option.value == selected,
                  onTap: () {
                    PortyHapticsService.maybeOf(context)?.selectionTap();
                    onSelected(option.value);
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionalTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Text(
        'investor_profile_optional_tag'.tr(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

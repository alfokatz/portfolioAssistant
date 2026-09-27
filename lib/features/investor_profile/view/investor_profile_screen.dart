import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/investor_profile/view/widgets/investor_profile_option_row.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

/// Ajustes → Perfil de inversor. Única entrada para completar el perfil la
/// primera vez y para editarlo después (también se llega desde el aviso de
/// Porty en el chat, que empuja esta misma ruta).
///
/// Una sola pantalla con las tres preguntas a la vista — sin wizard ni
/// barra de progreso: son tres elecciones cortas y el usuario casual las
/// completa de un vistazo.
class InvestorProfileScreen extends StatefulHookConsumerWidget {
  const InvestorProfileScreen({super.key});

  @override
  ConsumerState<InvestorProfileScreen> createState() =>
      _InvestorProfileScreenState();
}

class _InvestorProfileScreenState
    extends BaseStatefulWidget<InvestorProfileScreen> {
  // Se empuja por encima del shell, que sigue montado y ya escucha las
  // alertas globales: suscribirse acá también las mostraría dos veces.
  @override
  bool get subscribesToGlobalEvents => false;

  RiskTolerance? _risk;
  InvestmentHorizon? _horizon;
  InvestmentObjective? _objective;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _prefill(ref.read(investorProfileProvider).profile);
    runAfterPostFrameCallback(() async {
      final profile =
          await ref.read(investorProfileProvider.notifier).refresh();
      // Solo completa lo que el usuario todavía no tocó.
      if (mounted && _risk == null && _horizon == null && _objective == null) {
        setState(() => _prefill(profile));
      }
    });
  }

  void _prefill(InvestorProfile? profile) {
    if (profile == null) return;
    _risk = profile.risk;
    _horizon = profile.horizon;
    _objective = profile.objective;
  }

  bool get _isComplete =>
      _risk != null && _horizon != null && _objective != null;

  Future<void> _save() async {
    if (!_isComplete) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await ref.read(investorProfileProvider.notifier).save(
            risk: _risk!,
            horizon: _horizon!,
            objective: _objective!,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'investor_profile_saved'.tr());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final colors = context.customColors;
    final textTheme = Theme.of(context).textTheme;
    final profileState = ref.watch(investorProfileProvider);
    final saved = profileState.profile;
    final isStale =
        profileState.statusAt(DateTime.now()) == InvestorProfileStatus.stale;

    return Scaffold(
      appBar: AppBar(title: Text('settings_investor_profile'.tr())),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          AppDimens.sp8,
          AppDimens.pageHorizontal,
          AppDimens.sp24,
        ),
        children: [
          Text(
            'investor_profile_intro'.tr(),
            style: textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          if (saved != null) ...[
            const SizedBox(height: AppDimens.sp8),
            Text(
              isStale
                  ? 'investor_profile_stale_notice'.tr()
                  : 'investor_profile_last_updated'.tr(
                    args: [
                      DateFormat.yMMMd(
                        context.locale.toLanguageTag(),
                      ).format(saved.updatedAt.toLocal()),
                    ],
                  ),
              style: textTheme.bodySmall?.copyWith(
                color: isStale ? colors.textPrimary : colors.textSecondary,
                fontWeight: isStale ? FontWeight.w500 : null,
              ),
            ),
          ],
          const SizedBox(height: AppDimens.sectionGap),
          _QuestionGroup<RiskTolerance>(
            title: 'investor_profile_q_risk'.tr(),
            selected: _risk,
            onSelected: (value) => setState(() => _risk = value),
            options: [
              for (final risk in RiskTolerance.values)
                (
                  value: risk,
                  label: 'investor_profile_risk_${risk.storageValue}'.tr(),
                  description:
                      'investor_profile_risk_${risk.storageValue}_desc'.tr(),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.sectionGap),
          _QuestionGroup<InvestmentHorizon>(
            title: 'investor_profile_q_horizon'.tr(),
            selected: _horizon,
            onSelected: (value) => setState(() => _horizon = value),
            options: [
              for (final horizon in InvestmentHorizon.values)
                (
                  value: horizon,
                  label:
                      'investor_profile_horizon_${horizon.storageValue}'.tr(),
                  description:
                      'investor_profile_horizon_${horizon.storageValue}_desc'
                          .tr(),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.sectionGap),
          _QuestionGroup<InvestmentObjective>(
            title: 'investor_profile_q_objective'.tr(),
            selected: _objective,
            onSelected: (value) => setState(() => _objective = value),
            options: [
              for (final objective in InvestmentObjective.values)
                (
                  value: objective,
                  label:
                      'investor_profile_objective_${objective.storageValue}'
                          .tr(),
                  description:
                      'investor_profile_objective_${objective.storageValue}_desc'
                          .tr(),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp12,
            AppDimens.pageHorizontal,
            AppDimens.sp16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saveFailed) ...[
                Text(
                  'investor_profile_save_error'.tr(),
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(color: colors.loss),
                ),
                const SizedBox(height: AppDimens.sp8),
              ],
              PositionPrimaryButton(
                label: 'investor_profile_save'.tr(),
                loading: _saving,
                onPressed: _isComplete ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionGroup<T> extends StatelessWidget {
  const _QuestionGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final List<({T value, String label, String description})> options;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(height: AppDimens.sp12),
        for (final (i, option) in options.indexed) ...[
          if (i > 0) const SizedBox(height: AppDimens.sp8),
          InvestorProfileOptionRow(
            label: option.label,
            description: option.description,
            isSelected: option.value == selected,
            onTap: () => onSelected(option.value),
          ),
        ],
      ],
    );
  }
}

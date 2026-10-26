import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/porty_chat_sheet.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/domain/portfolio_diagnosis.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/diagnosis_copy.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/statement_import/nav/statement_import_router.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

/// "Lo que vi en tu cartera": el primer diagnóstico, apenas carga la
/// cartera. Porty cuenta hasta 3 cosas que no se ven a simple vista
/// (calculadas en la app, sin el modelo) y deja preguntas para seguir en el
/// chat. Funciona igual en Free.
class PortfolioDiagnosisScreen extends ConsumerStatefulWidget {
  const PortfolioDiagnosisScreen({super.key});

  @override
  ConsumerState<PortfolioDiagnosisScreen> createState() =>
      _PortfolioDiagnosisScreenState();
}

class _PortfolioDiagnosisScreenState
    extends ConsumerState<PortfolioDiagnosisScreen> {
  /// Con 2 posiciones o menos, Porty ve poco: invita a sumar el resto.
  static const _fewPositions = 2;

  /// Cuántas preguntas para seguir en el chat.
  static const _maxQuestions = 2;

  bool _logged = false;

  void _onLoaded(PortfolioDiagnosis d) {
    if (_logged || d.findings.isEmpty) return;
    _logged = true;
    unawaited(ref.read(diagnosisSeenProvider.notifier).markSeen());
    ref.read(productEventsProvider).log(ProductEvent.diagnosisSeen, {
      'findings': [for (final f in d.findings) f.kind.name],
      'positions': d.positions,
    });
  }

  void _close() {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed(HomeRouter.homeRouteName);
    }
  }

  void _ask(DiagnosisFinding finding) {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    ref.read(productEventsProvider).log(ProductEvent.diagnosisQuestion, {
      'kind': finding.kind.name,
    });
    unawaited(
      PortyChatSheet.show(
        context,
        question: DiagnosisCopy.question(finding),
        screen: const PortyScreenContext(PortyScreen.diagnosis),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(portfolioDiagnosisProvider);
    ref.listen(portfolioDiagnosisProvider, (_, next) {
      if (next case AsyncData(:final value)) _onLoaded(value);
    });
    // Ya estaba cargado al entrar (no hubo cambio que escuchar).
    if (async case AsyncData(:final value) when !_logged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onLoaded(value);
      });
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'diagnosis_close'.tr(),
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.pageHorizontal,
                  0,
                  AppDimens.pageHorizontal,
                  AppDimens.sp24,
                ),
                children: [
                  LoadingSwitcher(
                    loading: async.isLoading,
                    placeholder: (_) => const _DiagnosisSkeleton(),
                    child:
                        (_) => switch (async) {
                          AsyncData(:final value)
                              when value.findings.isNotEmpty =>
                            _DiagnosisBody(
                              diagnosis: value,
                              fewPositions: value.positions <= _fewPositions,
                              maxQuestions: _maxQuestions,
                              onAsk: _ask,
                            ),
                          _ => _DiagnosisUnavailable(
                            onRetry:
                                () =>
                                    ref.invalidate(portfolioDiagnosisProvider),
                          ),
                        },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                AppDimens.sp8,
                AppDimens.pageHorizontal,
                AppDimens.sp16,
              ),
              child: PositionPrimaryButton(
                label: 'diagnosis_cta_done'.tr(),
                onPressed: _close,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosisBody extends StatelessWidget {
  const _DiagnosisBody({
    required this.diagnosis,
    required this.fewPositions,
    required this.maxQuestions,
    required this.onAsk,
  });

  final PortfolioDiagnosis diagnosis;
  final bool fewPositions;
  final int maxQuestions;
  final void Function(DiagnosisFinding) onAsk;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final findings = diagnosis.findings;
    var order = 0;
    Widget enter(Widget child) =>
        FadeSlideIn(delay: Duration(milliseconds: 80 * order++), child: child);
    final divider = Divider(
      height: 1,
      thickness: 1,
      indent: _FindingRow.iconBox + AppDimens.sp16,
      color: colors.border,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppDimens.sp8),
        enter(
          PortySays(
            message: Text(DiagnosisCopy.headline(diagnosis)),
            messageKey: findings.length,
            mood:
                diagnosis.anyAttention
                    ? PortyAvatarState.idle
                    : PortyAvatarState.answered,
          ),
        ),
        const SizedBox(height: AppDimens.sectionGap),
        for (final (i, f) in findings.indexed) ...[
          if (i > 0) divider,
          enter(_FindingRow(finding: f)),
        ],
        if (fewPositions) ...[
          divider,
          enter(
            _FindingRow.action(
              icon: Icons.add_rounded,
              title: 'diagnosis_few_title'.tr(),
              detail: 'diagnosis_few_detail'.tr(
                namedArgs: {'count': '${diagnosis.positions}'},
              ),
              onTap: () {
                PortyHapticsService.maybeOf(context)?.selectionTap();
                context.pushNamed(StatementImportRouter.routeName);
              },
            ),
          ),
        ],
        const SizedBox(height: AppDimens.sectionGap),
        enter(
          Padding(
            padding: const EdgeInsets.only(
              left: AppDimens.sp4,
              bottom: AppDimens.sp8,
            ),
            child: Text(
              'diagnosis_ask_header'.tr(),
              style: tt.labelLarge?.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        enter(
          _QuestionGroup(
            questions: findings.take(maxQuestions).toList(),
            onAsk: onAsk,
          ),
        ),
        const SizedBox(height: AppDimens.sp20),
        enter(
          Text(
            'diagnosis_note'.tr(),
            style: tt.bodySmall?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/// Un hallazgo: el ícono en el círculo silencioso de las filas, el título
/// con el número y una línea que lo explica. Directo sobre el fondo.
class _FindingRow extends StatelessWidget {
  const _FindingRow({required DiagnosisFinding this.finding})
    : icon = null,
      title = null,
      detail = null,
      onTap = null;

  /// Una fila que lleva a hacer algo (sumar el resto de la cartera).
  const _FindingRow.action({
    required IconData this.icon,
    required String this.title,
    required String this.detail,
    required VoidCallback this.onTap,
  }) : finding = null;

  final DiagnosisFinding? finding;
  final IconData? icon;
  final String? title;
  final String? detail;
  final VoidCallback? onTap;

  static const iconBox = 36.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final f = finding;
    final iconColor = switch (f?.tone) {
      DiagnosisTone.attention => colors.accentWarm,
      DiagnosisTone.good => colors.profit,
      _ => colors.onChip,
    };
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: iconBox,
            height: iconBox,
            decoration: BoxDecoration(
              color: colors.chip,
              shape: BoxShape.circle,
            ),
            child: Icon(
              f == null ? icon : DiagnosisCopy.icon(f),
              size: AppDimens.iconSm,
              color: iconColor,
            ),
          ),
          const SizedBox(width: AppDimens.sp16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f == null ? title! : DiagnosisCopy.title(f),
                  style: tt.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppDimens.sp4),
                Text(
                  f == null ? detail! : DiagnosisCopy.detail(f),
                  style: tt.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppDimens.sp8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: AppDimens.iconSm,
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return Semantics(container: true, child: row);
    return Semantics(button: true, child: InkWell(onTap: onTap, child: row));
  }
}

/// Las preguntas para seguir en el chat: un grupo como las sugerencias del
/// chat (card con borde, filas con ↗).
class _QuestionGroup extends StatelessWidget {
  const _QuestionGroup({required this.questions, required this.onAsk});

  final List<DiagnosisFinding> questions;
  final void Function(DiagnosisFinding) onAsk;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, f) in questions.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppDimens.sp16 + PortySays.avatarSize / 2 + 12,
                endIndent: AppDimens.sp16,
                color: colors.border,
              ),
            Semantics(
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onAsk(f),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.sp16,
                        vertical: AppDimens.sp12,
                      ),
                      child: Row(
                        children: [
                          const ExcludeSemantics(child: PortyAvatar(size: 22)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              DiagnosisCopy.question(f),
                              style: tt.bodyMedium?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: AppDimens.sp8),
                          ExcludeSemantics(
                            child: Icon(
                              Icons.north_east_rounded,
                              size: AppDimens.iconSm,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
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
}

/// Sin datos (sin red, cotizaciones caídas): Porty lo dice y deja
/// reintentar. La cartera está igual en la Home.
class _DiagnosisUnavailable extends StatelessWidget {
  const _DiagnosisUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppDimens.sp8),
        PortySays(
          message: Text('diagnosis_unavailable'.tr()),
          messageKey: 'unavailable',
          mood: PortyAvatarState.concerned,
        ),
        const SizedBox(height: AppDimens.sp16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: colors.textPrimary,
              minimumSize: const Size(
                AppDimens.touchTarget,
                AppDimens.touchTarget,
              ),
            ),
            child: Text('retry'.tr()),
          ),
        ),
      ],
    );
  }
}

/// La misma forma que el diagnóstico: Porty y tres filas.
class _DiagnosisSkeleton extends StatelessWidget {
  const _DiagnosisSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      semanticsLabel: 'diagnosis_loading'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppDimens.sp8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBlock(
                width: PortySays.avatarSize,
                height: PortySays.avatarSize,
                radius: PortySays.avatarSize / 2,
              ),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppDimens.sp8),
                    Text(
                      'diagnosis_loading'.tr(),
                      style: PortySays.style(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sectionGap),
          for (var i = 0; i < 3; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppDimens.sp16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBlock(
                    width: _FindingRow.iconBox,
                    height: _FindingRow.iconBox,
                    radius: _FindingRow.iconBox / 2,
                  ),
                  SizedBox(width: AppDimens.sp16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBlock(width: 220, height: 16),
                        SizedBox(height: AppDimens.sp8),
                        SkeletonBlock(height: 12),
                        SizedBox(height: AppDimens.sp4),
                        SkeletonBlock(width: 160, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

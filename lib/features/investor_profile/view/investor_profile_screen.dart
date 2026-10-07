import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/investor_profile/view/widgets/profile_questions.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';

/// Ajustes → Perfil de inversor (también se llega desde el aviso de Porty
/// en el chat). Dos modos, decididos una sola vez al abrir:
/// - sin perfil: un carrusel en el que Porty pregunta de a una (las tres
///   necesarias y dos opcionales) y cierra con un "listo";
/// - con perfil: un resumen ("Esto es lo que sé de vos") donde cada
///   respuesta se cambia sola, sin volver a pasar por todas.
class InvestorProfileScreen extends StatefulHookConsumerWidget {
  const InvestorProfileScreen({super.key});

  @override
  ConsumerState<InvestorProfileScreen> createState() =>
      _InvestorProfileScreenState();
}

enum _Mode { wizard, summary }

class _InvestorProfileScreenState
    extends BaseStatefulWidget<InvestorProfileScreen> {
  // Se empuja por encima del shell, que sigue montado y ya escucha las
  // alertas globales: suscribirse acá también las mostraría dos veces.
  @override
  bool get subscribesToGlobalEvents => false;

  /// Fijo una vez decidido: al terminar el carrusel el perfil ya existe, y
  /// la pantalla no puede saltar al resumen en medio del cierre.
  _Mode? _mode;

  @override
  void initState() {
    super.initState();
    final state = ref.read(investorProfileProvider);
    if (state.hasLoaded) _mode = _modeFor(state);
    runAfterPostFrameCallback(() async {
      await ref.read(investorProfileProvider.notifier).refresh();
      if (!mounted || _mode != null) return;
      setState(() => _mode = _modeFor(ref.read(investorProfileProvider)));
    });
  }

  _Mode _modeFor(InvestorProfileState state) =>
      state.profile == null ? _Mode.wizard : _Mode.summary;

  @override
  Widget buildView(BuildContext context) {
    return switch (_mode) {
      null => Scaffold(
        appBar: AppBar(),
        body: Center(child: PortyLoader(message: 'loader_one_moment'.tr())),
      ),
      _Mode.wizard => const _ProfileWizard(),
      _Mode.summary => const _ProfileSummary(),
    };
  }
}

/// Guarda [answers] y avisa si falló. `true` si salió bien.
Future<bool> _saveAnswers(WidgetRef ref, ProfileAnswers answers) async {
  if (!answers.isComplete) return false;
  try {
    await ref.read(investorProfileProvider.notifier).save(
      risk: answers.risk!,
      horizon: answers.horizon!,
      objective: answers.objective!,
      experience: answers.experience,
      drawdownReaction: answers.drawdown,
    );
    return true;
  } catch (_) {
    ref
        .read(alertProvider.notifier)
        .showError(message: 'investor_profile_save_error'.tr());
    return false;
  }
}

// ---------------------------------------------------------------------------
// Primera vez: el carrusel
// ---------------------------------------------------------------------------

class _ProfileWizard extends ConsumerStatefulWidget {
  const _ProfileWizard();

  @override
  ConsumerState<_ProfileWizard> createState() => _ProfileWizardState();
}

class _ProfileWizardState extends ConsumerState<_ProfileWizard> {
  static const _questions = ProfileQuestion.values;

  final _pages = PageController();
  var _answers = const ProfileAnswers();
  int _page = 0;
  bool _saving = false;

  bool get _done => _page == _questions.length;
  ProfileQuestion get _question => _questions[_page];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Duration get _slide =>
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300);

  void _goTo(int page) {
    setState(() => _page = page);
    _pages.animateToPage(page, duration: _slide, curve: Curves.easeOutCubic);
  }

  /// Elegir avanza solo (después de un instante, para ver la elección).
  void _select(Object value) {
    final page = _page;
    setState(() => _answers = _question.answer(_answers, value));
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (mounted && _page == page) _next();
    });
  }

  Future<void> _next() async {
    if (_page < _questions.length - 1) {
      _goTo(_page + 1);
      return;
    }
    setState(() => _saving = true);
    final ok = await _saveAnswers(ref, _answers);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) _goTo(_questions.length);
  }

  void _skip() {
    setState(() => _answers = _question.answer(_answers, null));
    _next();
  }

  void _back() {
    if (_page > 0 && !_done) {
      _goTo(_page - 1);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final answered = !_done && _question.valueIn(_answers) != null;

    return PopScope(
      // "Atrás" vuelve a la pregunta anterior antes de salir.
      canPop: _page == 0 || _done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading:
              _done
                  ? const SizedBox.shrink()
                  : IconButton(
                    icon: const BackButtonIcon(),
                    onPressed: _back,
                  ),
          bottom:
              _done
                  ? null
                  : PreferredSize(
                    preferredSize: const Size.fromHeight(3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.pageHorizontal,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            end: (_page + 1) / _questions.length,
                          ),
                          duration: _slide,
                          builder:
                              (context, value, _) => LinearProgressIndicator(
                                value: value,
                                minHeight: 3,
                                color: colors.accentBlue,
                                backgroundColor: colors.surfaceElevated,
                              ),
                        ),
                      ),
                    ),
                  ),
        ),
        body: PageView(
          controller: _pages,
          // Se avanza eligiendo (las necesarias no se pueden saltear).
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final (i, question) in _questions.indexed)
              ProfileQuestionView(
                question: question,
                selected: question.valueIn(_answers),
                onSelected: _select,
                eyebrow: 'investor_profile_step'.tr(
                  namedArgs: {
                    'current': '${i + 1}',
                    'total': '${_questions.length}',
                  },
                ),
                intro: i == 0 ? 'investor_profile_wizard_intro'.tr() : null,
              ),
            _ProfileDone(answers: _answers),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              AppDimens.sp8,
              AppDimens.pageHorizontal,
              AppDimens.sp16,
            ),
            child:
                _done
                    ? PositionPrimaryButton(
                      label: 'investor_profile_done_cta'.tr(),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                    : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PositionPrimaryButton(
                          label:
                              _page == _questions.length - 1
                                  ? 'investor_profile_save'.tr()
                                  : 'investor_profile_next'.tr(),
                          loading: _saving,
                          onPressed: answered && !_saving ? _next : null,
                        ),
                        if (_question.isOptional) ...[
                          const SizedBox(height: AppDimens.sp8),
                          TextButton(
                            onPressed: _saving ? null : _skip,
                            child: Text(
                              'investor_profile_skip'.tr(),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          ),
                        ],
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}

/// El cierre del carrusel: Porty contento y lo que ahora sabe.
class _ProfileDone extends StatelessWidget {
  const _ProfileDone({required this.answers});

  final ProfileAnswers answers;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp24,
        AppDimens.pageHorizontal,
        AppDimens.sp24,
      ),
      children: [
        const Center(
          child: ExcludeSemantics(
            child: PortyAvatar(
              size: 88,
              state: PortyAvatarState.answered,
              animated: true,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp20),
        Semantics(
          header: true,
          child: Text(
            'investor_profile_done_title'.tr(),
            textAlign: TextAlign.center,
            style: tt.displaySmall?.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          'investor_profile_done_body'.tr(),
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: colors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppDimens.sp24),
        _AnswersCard(answers: answers),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Perfil completo: el resumen
// ---------------------------------------------------------------------------

class _ProfileSummary extends ConsumerWidget {
  const _ProfileSummary();

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ProfileQuestion question,
  ) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EditQuestionScreen(question)),
    );
    if (saved == true) {
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'investor_profile_saved'.tr());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final state = ref.watch(investorProfileProvider);
    final profile = state.profile;
    final answers = ProfileAnswers.of(profile);
    final isStale =
        state.statusAt(DateTime.now()) == InvestorProfileStatus.stale;

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp32,
        ),
        children: [
          Row(
            children: [
              const ExcludeSemantics(
                child: PortyAvatar(size: 56, animated: true),
              ),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'investor_profile_summary_title'.tr(),
                    style: tt.displaySmall?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.2,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp12),
          Text(
            'investor_profile_summary_body'.tr(),
            style: tt.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          if (profile != null) ...[
            const SizedBox(height: AppDimens.sp4),
            Text(
              isStale
                  ? 'investor_profile_stale_notice'.tr()
                  : 'investor_profile_last_updated'.tr(
                    args: [
                      DateFormat.yMMMd(
                        Localizations.localeOf(context).toLanguageTag(),
                      ).format(profile.updatedAt.toLocal()),
                    ],
                  ),
              style: tt.bodySmall?.copyWith(
                color: isStale ? colors.textPrimary : colors.textSecondary,
                fontWeight: isStale ? FontWeight.w600 : null,
              ),
            ),
          ],
          const SizedBox(height: AppDimens.sp20),
          _AnswersCard(
            answers: answers,
            onTap: (question) => _edit(context, ref, question),
          ),
          if (isStale) ...[
            const SizedBox(height: AppDimens.sp20),
            // Volver a guardar lo mismo renueva la fecha.
            _ConfirmStaleButton(answers: answers),
          ],
        ],
      ),
    );
  }
}

class _ConfirmStaleButton extends ConsumerStatefulWidget {
  const _ConfirmStaleButton({required this.answers});

  final ProfileAnswers answers;

  @override
  ConsumerState<_ConfirmStaleButton> createState() =>
      _ConfirmStaleButtonState();
}

class _ConfirmStaleButtonState extends ConsumerState<_ConfirmStaleButton> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) => PositionPrimaryButton(
    label: 'investor_profile_confirm'.tr(),
    loading: _saving,
    onPressed:
        _saving
            ? null
            : () async {
              setState(() => _saving = true);
              final ok = await _saveAnswers(ref, widget.answers);
              if (!mounted) return;
              setState(() => _saving = false);
              if (ok) {
                ref
                    .read(alertProvider.notifier)
                    .showSuccess(message: 'investor_profile_saved'.tr());
              }
            },
  );
}

/// Cambiar UNA respuesta desde el resumen: la misma pregunta del carrusel;
/// elegir guarda y vuelve.
class _EditQuestionScreen extends ConsumerStatefulWidget {
  const _EditQuestionScreen(this.question);

  final ProfileQuestion question;

  @override
  ConsumerState<_EditQuestionScreen> createState() =>
      _EditQuestionScreenState();
}

class _EditQuestionScreenState extends ConsumerState<_EditQuestionScreen> {
  bool _saving = false;

  Future<void> _save(Object? value) async {
    if (_saving) return;
    setState(() => _saving = true);
    final current = ProfileAnswers.of(ref.read(investorProfileProvider).profile);
    final ok = await _saveAnswers(
      ref,
      widget.question.answer(current, value),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final answers = ProfileAnswers.of(
      ref.watch(investorProfileProvider).profile,
    );
    return Scaffold(
      appBar: AppBar(),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ProfileQuestionView(
          question: widget.question,
          selected: widget.question.valueIn(answers),
          onSelected: _save,
        ),
      ),
      bottomNavigationBar:
          widget.question.isOptional &&
                  widget.question.valueIn(answers) != null
              ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppDimens.sp8),
                  child: TextButton(
                    onPressed: _saving ? null : () => _save(null),
                    child: Text(
                      'investor_profile_clear'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ),
                ),
              )
              : null,
    );
  }
}

/// Las respuestas como filas ("Riesgo · Agresivo"). Con [onTap], cada fila
/// abre su pregunta.
class _AnswersCard extends StatelessWidget {
  const _AnswersCard({required this.answers, this.onTap});

  final ProfileAnswers answers;
  final ValueChanged<ProfileQuestion>? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final onTap = this.onTap;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (final (i, question) in ProfileQuestion.values.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppDimens.cardPadding,
                endIndent: AppDimens.cardPadding,
                color: colors.border,
              ),
            Semantics(
              button: onTap != null,
              child: InkWell(
                onTap: onTap == null ? null : () => onTap(question),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppDimens.touchTarget + 8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.cardPadding,
                      vertical: AppDimens.sp12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                question.shortLabel,
                                style: tt.bodySmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                question.answerLabel(answers) ??
                                    'investor_profile_unanswered'.tr(),
                                style: tt.bodyLarge?.copyWith(
                                  color:
                                      question.answerLabel(answers) == null
                                          ? colors.textSecondary
                                          : colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onTap != null)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: AppDimens.iconMd,
                            color: colors.textSecondary,
                          ),
                      ],
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

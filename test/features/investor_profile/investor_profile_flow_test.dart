import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/repositories/investor_profile_repository.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/investor_profile/view/investor_profile_screen.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

class _Repo implements InvestorProfileRepository {
  _Repo(this.stored);
  InvestorProfile? stored;
  var saves = 0;

  @override
  Future<InvestorProfile?> fetch() async => stored;

  @override
  Future<InvestorProfile> save({
    required RiskTolerance risk,
    required InvestmentHorizon horizon,
    required InvestmentObjective objective,
    InvestmentExperience? experience,
    DrawdownReaction? drawdownReaction,
    Map<String, String> notes = const {},
  }) async {
    saves++;
    return stored = InvestorProfile(
      risk: risk,
      horizon: horizon,
      objective: objective,
      updatedAt: DateTime(2026, 10, 7),
      experience: experience,
      drawdownReaction: drawdownReaction,
      notes: notes,
    );
  }
}

class _Auth implements SupabaseAuthService {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Notifier extends InvestorProfileNotifier {
  _Notifier(this.repo) : super(repository: repo, authService: _Auth());
  final _Repo repo;

  @override
  Future<InvestorProfile?> refresh() async {
    state = InvestorProfileState(profile: repo.stored, hasLoaded: true);
    return repo.stored;
  }
}

/// Sin easy_localization cargado, `.tr()` devuelve la key.
Future<void> _open(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(393, 1000) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [investorProfileProvider.overrideWith((ref) => _Notifier(repo))],
  );
  addTearDown(container.dispose);
  // En la app, el shell escucha las alertas (si no, el provider se
  // descarta solo).
  container.listen(alertProvider, (_, __) {});
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: container.read(themeDataLightProvider),
        home: const InvestorProfileScreen(),
      ),
    ),
  );
  await _settle(tester);
}

/// Porty respira (animación continua): sin pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await _settle(tester);
}

/// Las preguntas con texto libre no avanzan solas: se confirma con el botón.
Future<void> _tapButton(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await _settle(tester);
}

void main() {
  testWidgets('without a profile: Porty asks one question at a time, '
      'choosing moves on, the optional ones can be skipped, and it ends '
      'with a "done"', (tester) async {
    final repo = _Repo(null);
    await _open(tester, repo);

    expect(find.text('investor_profile_q_risk'), findsOneWidget);
    expect(find.text('investor_profile_wizard_intro'), findsOneWidget);
    await _choose(tester, 'investor_profile_risk_aggressive');
    expect(find.text('investor_profile_q_horizon'), findsOneWidget);
    await _choose(tester, 'investor_profile_horizon_long');
    // Horizonte admite texto libre: elegir no avanza, Siguiente sí.
    expect(find.text('investor_profile_q_horizon'), findsOneWidget);
    expect(find.text('investor_profile_note_label'), findsOneWidget);
    await _tapButton(tester, 'investor_profile_next');
    await _choose(tester, 'investor_profile_objective_specific_goal');
    await tester.enterText(
      find.byType(TextField),
      'Quiero comprarme una compu el año que viene',
    );
    await _settle(tester);
    await _tapButton(tester, 'investor_profile_next');

    // Opcionales: se saltean.
    expect(find.text('investor_profile_q_experience'), findsOneWidget);
    expect(find.text('investor_profile_optional_tag'), findsOneWidget);
    await tester.tap(find.text('investor_profile_skip'));
    await _settle(tester);
    expect(find.text('investor_profile_q_drawdown'), findsOneWidget);
    await tester.tap(find.text('investor_profile_skip'));
    await _settle(tester);

    expect(repo.saves, 1);
    expect(repo.stored!.risk, RiskTolerance.aggressive);
    expect(repo.stored!.horizon, InvestmentHorizon.long);
    expect(repo.stored!.experience, isNull);
    expect(repo.stored!.notes, {
      'objective': 'Quiero comprarme una compu el año que viene',
    });
    expect(find.text('investor_profile_done_title'), findsOneWidget);
  });

  testWidgets('back goes to the previous question, keeping the answer', (
    tester,
  ) async {
    await _open(tester, _Repo(null));
    await _choose(tester, 'investor_profile_risk_moderate');
    expect(find.text('investor_profile_q_horizon'), findsOneWidget);

    await tester.tap(find.byType(BackButtonIcon));
    await _settle(tester);
    expect(find.text('investor_profile_q_risk'), findsOneWidget);
    // La elegida sigue marcada: "Siguiente" está habilitado.
    final next = find.text('investor_profile_next');
    await tester.tap(next);
    await _settle(tester);
    expect(find.text('investor_profile_q_horizon'), findsOneWidget);
  });

  testWidgets('with a profile: the summary; changing one answer saves only '
      'that and keeps the rest', (tester) async {
    final repo = _Repo(
      InvestorProfile(
        risk: RiskTolerance.aggressive,
        horizon: InvestmentHorizon.medium,
        objective: InvestmentObjective.growth,
        updatedAt: DateTime(2026, 9, 26),
        experience: InvestmentExperience.beginner,
      ),
    );
    await _open(tester, repo);

    expect(find.text('investor_profile_summary_title'), findsOneWidget);
    expect(find.text('investor_profile_risk_aggressive'), findsOneWidget);
    expect(find.text('investor_profile_unanswered'), findsOneWidget); // caída

    await tester.tap(find.text('investor_profile_label_horizon'));
    await _settle(tester);
    expect(find.text('investor_profile_q_horizon'), findsOneWidget);
    await _choose(tester, 'investor_profile_horizon_long');
    // Con texto libre, se guarda con el botón (junto con la nota).
    expect(repo.saves, 0);
    await tester.enterText(find.byType(TextField), 'Para dentro de 10 años');
    await _tapButton(tester, 'investor_profile_save');

    expect(repo.saves, 1);
    expect(repo.stored!.notes, {'horizon': 'Para dentro de 10 años'});
    expect(repo.stored!.horizon, InvestmentHorizon.long);
    expect(repo.stored!.risk, RiskTolerance.aggressive);
    expect(repo.stored!.experience, InvestmentExperience.beginner);
    expect(find.text('investor_profile_summary_title'), findsOneWidget);
    expect(find.text('investor_profile_horizon_long'), findsOneWidget);
  });
}

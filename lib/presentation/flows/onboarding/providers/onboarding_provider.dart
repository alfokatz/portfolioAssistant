import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';

enum OnboardingExit { home, addPosition, assistant }

class OnboardingNotifier {
  OnboardingNotifier(this._ref);

  final Ref _ref;

  Future<void> markComplete() async {
    await _ref
        .read(preferenceManagerProvider)
        .setOnboardingCompleted(completed: true);
  }

  Future<void> reset() async {
    await _ref
        .read(preferenceManagerProvider)
        .setOnboardingCompleted(completed: false);
  }
}

final onboardingProvider = Provider<OnboardingNotifier>(
  (ref) => OnboardingNotifier(ref),
);

final onboardingCompletedProvider = Provider<bool>(
  (ref) => ref.watch(preferenceManagerProvider).hasCompletedOnboarding(),
);

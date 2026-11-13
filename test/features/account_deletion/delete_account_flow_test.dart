// Flujo de "Eliminar cuenta": aviso de suscripción, confirmación, progreso,
// éxito con cierre de sesión y cada falla con su texto. Fakes a mano.
// Correr: flutter test test/features/account_deletion
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/account_deletion/data/account_deletion_repository.dart';
import 'package:portfolio_assistant/features/account_deletion/data/subscription_store_probe.dart';
import 'package:portfolio_assistant/features/account_deletion/domain/account_deletion.dart';
import 'package:portfolio_assistant/features/account_deletion/providers/account_deletion_provider.dart';
import 'package:portfolio_assistant/features/account_deletion/view/widgets/delete_account_flow.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Store;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRepo implements AccountDeletionRepository {
  _FakeRepo(this.result);

  Future<AccountDeletionFailure?> Function() result;
  int calls = 0;

  @override
  Future<AccountDeletionFailure?> deleteAccount({
    String? appleAuthorizationCode,
  }) {
    calls++;
    return result();
  }
}

class _FakeAuth implements SupabaseAuthService {
  _FakeAuth(this.user);

  final User? user;
  int signOutLocalCalls = 0;

  @override
  User? get currentUser => user;

  @override
  Future<void> signOutLocal() async => signOutLocalCalls++;

  @override
  bool get canRevokeApple => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User _user({List<String> providers = const ['email']}) => User(
  id: 'uid-1',
  appMetadata: {'providers': providers},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

void loadSpanish() {
  Localization.load(
    const Locale('es', 'ES'),
    translations: Translations(
      jsonDecode(File('assets/translations/es-ES.json').readAsStringSync()),
    ),
    ignorePluralRules: false,
  );
}

class _Harness {
  _Harness({
    List<Store> stores = const [],
    SubscriptionTier tier = SubscriptionTier.free,
    User? user,
    Future<AccountDeletionFailure?> Function()? delete,
    this.launchResult = true,
  }) : repo = _FakeRepo(delete ?? () async => null),
       auth = _FakeAuth(user ?? _user()),
       _stores = stores,
       _tier = tier;

  final _FakeRepo repo;
  final _FakeAuth auth;
  final List<Store> _stores;
  final SubscriptionTier _tier;
  final bool launchResult;
  final launched = <Uri>[];
  final toasts = <String>[];
  late ProviderContainer container;
  late SharedPreferences prefs;

  Future<void> pump(WidgetTester tester, {bool dark = false}) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'home_snapshot_v1_uid-1': 'x',
      'weekly_report_seen_uid-1_2026-W44': true,
      'portfolio_diagnosis_seen:uid-1': true,
      'theme_mode': 'dark',
      'home_snapshot_v1_other': 'y',
    });
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        accountDeletionRepositoryProvider.overrideWithValue(repo),
        subscriptionStoreProbeProvider.overrideWithValue(
          SubscriptionStoreProbe(
            isConfigured: () => true,
            serverTier: () => _tier,
            activeStores: () async => _stores,
          ),
        ),
        supabaseAuthServiceProvider.overrideWithValue(auth),
        sharedPreferencesProvider.overrideWithValue(prefs),
        storeLinkLauncherProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return launchResult;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(alertProvider, (_, next) {
      final message = next?.message;
      if (message != null) toasts.add(message);
    });

    final theme = ProviderContainer().read(
      dark ? themeDataDarkProvider : themeDataLightProvider,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (_, _) => Scaffold(
                body: Builder(
                  builder:
                      (context) => TextButton(
                        onPressed: () => DeleteAccountFlow.run(context),
                        child: const Text('open'),
                      ),
                ),
              ),
        ),
        GoRoute(path: '/login', builder: (_, _) => const Text('LOGIN')),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: theme, routerConfig: router),
      ),
    );
  }

  /// Abre el flujo hasta que la hoja de confirmación esté en pantalla.
  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> confirm(
    WidgetTester tester, {
    String label = 'settings_delete_account',
  }) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  group('DeleteAccountFlow subscription notice', () {
    testWidgets(
      'App Store: warning above the button, link opens outside and keeps the sheet',
      (tester) async {
        final h = _Harness(stores: [Store.appStore]);
        await h.pump(tester);
        await h.open(tester);

        expect(
          find.text('settings_delete_account_subscription_warning'),
          findsOneWidget,
        );
        expect(
          tester
              .getTopLeft(
                find.text('settings_delete_account_subscription_warning'),
              )
              .dy,
          lessThan(tester.getTopLeft(find.text('settings_delete_account')).dy),
        );

        await tester.tap(
          find.text('settings_delete_account_manage_subscription'),
        );
        await tester.pump();
        expect(
          h.launched.single.toString(),
          'https://apps.apple.com/account/subscriptions',
        );
        expect(find.text('settings_delete_account'), findsOneWidget);
        expect(h.repo.calls, 0);
      },
    );

    testWidgets('Google Play link', (tester) async {
      final h = _Harness(stores: [Store.playStore]);
      await h.pump(tester);
      await h.open(tester);
      await tester.tap(
        find.text('settings_delete_account_manage_subscription'),
      );
      await tester.pump();
      expect(
        h.launched.single.toString(),
        'https://play.google.com/store/account/subscriptions',
      );
    });

    testWidgets('a link that does not open shows an error toast', (
      tester,
    ) async {
      final h = _Harness(stores: [Store.playStore], launchResult: false);
      await h.pump(tester);
      await h.open(tester);
      await tester.tap(
        find.text('settings_delete_account_manage_subscription'),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.toasts, ['settings_link_error']);
    });

    testWidgets('generic: warning without a store link (dark, 375 wide)', (
      tester,
    ) async {
      final h = _Harness(
        stores: [Store.stripe],
        tier: SubscriptionTier.premium,
      );
      await h.pump(tester, dark: true);
      await h.open(tester);
      expect(
        find.text('settings_delete_account_subscription_warning_generic'),
        findsOneWidget,
      );
      expect(
        find.text('settings_delete_account_manage_subscription'),
        findsNothing,
      );
    });

    testWidgets('free user without entitlements sees no warning', (
      tester,
    ) async {
      final h = _Harness();
      await h.pump(tester);
      await h.open(tester);
      expect(find.text('settings_delete_account_title'), findsOneWidget);
      expect(find.textContaining('subscription_warning'), findsNothing);
    });

    testWidgets('cancel does not call the server', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await h.open(tester);
      await tester.tap(find.text('cancel'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.repo.calls, 0);
      expect(find.text('LOGIN'), findsNothing);
    });
  });

  group('DeleteAccountFlow result', () {
    testWidgets(
      'success: clears local data, signs out locally, goes to login, toast',
      (tester) async {
        final h = _Harness();
        await h.pump(tester);
        await h.open(tester);
        await h.confirm(tester);

        expect(h.repo.calls, 1);
        expect(h.auth.signOutLocalCalls, 1);
        expect(find.text('LOGIN'), findsOneWidget);
        expect(h.toasts, ['settings_delete_account_done']);
        expect(h.prefs.getKeys(), {'theme_mode', 'home_snapshot_v1_other'});
      },
    );

    testWidgets(
      'success for an Apple user: toast with the manual revocation guide',
      (tester) async {
        final h = _Harness(user: _user(providers: const ['email', 'apple']));
        await h.pump(tester);
        await h.open(tester);
        await h.confirm(tester);
        expect(find.text('LOGIN'), findsOneWidget);
        expect(h.toasts, ['settings_delete_account_done_apple']);
      },
    );

    testWidgets('nothing deleted: retry text, stays in the app', (
      tester,
    ) async {
      final h = _Harness(delete: () async => const DeletionNothingDeleted());
      await h.pump(tester);
      await h.open(tester);
      await h.confirm(tester);
      expect(h.toasts, ['settings_delete_account_error']);
      expect(h.auth.signOutLocalCalls, 0);
      expect(find.text('LOGIN'), findsNothing);
      expect(h.prefs.getKeys(), contains('home_snapshot_v1_uid-1'));
    });

    testWidgets('partial: support text, stays in the app', (tester) async {
      final h = _Harness(delete: () async => const DeletionPartial());
      await h.pump(tester);
      await h.open(tester);
      await h.confirm(tester);
      expect(h.toasts, ['settings_delete_account_error_partial']);
      expect(h.auth.signOutLocalCalls, 0);
      expect(find.text('LOGIN'), findsNothing);
    });

    testWidgets('session expired: local sign out, login, expired text', (
      tester,
    ) async {
      final h = _Harness(delete: () async => const DeletionSessionExpired());
      await h.pump(tester);
      await h.open(tester);
      await h.confirm(tester);
      expect(h.toasts, ['settings_delete_account_session_expired']);
      expect(h.auth.signOutLocalCalls, 1);
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('while running: non-dismissible progress, no second request', (
      tester,
    ) async {
      final gate = Completer<AccountDeletionFailure?>();
      final h = _Harness(delete: () => gate.future);
      await h.pump(tester);
      await h.open(tester);
      await h.confirm(tester);

      expect(find.text('settings_delete_account_in_progress'), findsOneWidget);
      expect(h.container.read(accountDeletionProvider).deleting, isTrue);
      expect(find.text('settings_delete_account'), findsNothing);

      // Tocar afuera no cierra la hoja de progreso.
      await tester.tapAt(const Offset(187, 20));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('settings_delete_account_in_progress'), findsOneWidget);

      // Un segundo pedido mientras corre el primero se ignora.
      expect(
        await h.container.read(accountDeletionProvider.notifier).delete(),
        isFalse,
      );
      expect(h.repo.calls, 1);

      gate.complete(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('settings_delete_account_in_progress'), findsNothing);
      expect(find.text('LOGIN'), findsOneWidget);
    });
  });

  testWidgets('real Spanish copy: partial error carries the support email', (
    tester,
  ) async {
    loadSpanish();
    final h = _Harness(
      stores: [Store.appStore],
      delete: () async => const DeletionPartial(),
    );
    await h.pump(tester);
    await h.open(tester);
    expect(
      find.text(
        'Tenés una suscripción activa en App Store. Borrar tu cuenta no la cancela: cancelala desde App Store para que no se te cobre de nuevo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Gestionar suscripción en App Store'), findsOneWidget);
    await h.confirm(tester, label: 'Eliminar cuenta');
    expect(
      h.toasts.single,
      startsWith('No pudimos terminar de eliminar tu cuenta.'),
    );
    expect(h.toasts.single, contains('soporte@'));
  });
}

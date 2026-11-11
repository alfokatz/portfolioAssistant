import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/porty_outfit/domain/porty_outfit.dart';
import 'package:portfolio_assistant/features/porty_outfit/providers/porty_outfit_provider.dart';
import 'package:portfolio_assistant/config/navigation/app_router.dart';
import 'package:portfolio_assistant/config/supabase/secure_auth_storage.dart';
import 'package:portfolio_assistant/config/supabase/session_scope.dart';
import 'package:portfolio_assistant/config/supabase/supabase_initializer.dart';
import 'package:portfolio_assistant/features/app_update/app_update_gate.dart';
import 'package:portfolio_assistant/features/app_update/app_update_required_screen.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_debug_log.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_background_refresh.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_launch_listener.dart';
import 'package:portfolio_assistant/features/notifications/data/push_messaging.dart';
import 'package:portfolio_assistant/features/notifications/providers/push_controller.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_initializer.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart'
    show themeDataDarkProvider, themeDataLightProvider;
import 'package:portfolio_assistant/presentation/base/theme/theme_mode_provider.dart';
import 'package:portfolio_assistant/presentation/shared/loading/app_bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

const _translationsPath = 'assets/translations';
const _dotenvBaseFolder = 'assets/env/';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  GenUiDebugLog.installLoggerBridge();
  // Antes del primer frame (sigue el splash nativo): el loader del arranque
  // tiene que salir con el tema elegido en Ajustes, no siempre con el del
  // sistema. Es una lectura local; `_initialize` reusa la misma instancia.
  final themeMode = ThemeModeNotifier.read(
    await SharedPreferences.getInstance(),
  );
  // El primer frame es Porty (el mismo del splash nativo) mientras se
  // inicializa todo; después, la app (ver AppBootstrap).
  runApp(AppBootstrap(initialize: _initialize, themeMode: themeMode));
}

/// Entorno, Supabase (restaura la sesión guardada), RevenueCat, idioma y
/// preferencias; devuelve la app lista para montar.
Future<Widget> _initialize() async {
  await _setupEnviroment();
  await SupabaseInitializer.initialize();
  // Con sesión restaurada: un toque del widget con una pregunta se atiende
  // al abrir; sin sesión, la pregunta se descarta tras el login.
  final launchedWithSession = Supabase.instance.client.auth.currentSession != null;
  // App Group del widget y refresco de fondo (workmanager).
  await initializeHomeWidgetPlugins();
  final revenueCatService = await RevenueCatInitializer.initialize();
  // Sin la configuración nativa de Firebase, la app funciona sin push.
  final pushMessaging = await FirebasePushMessaging.create();
  await EasyLocalization.ensureInitialized();
  // Nombres de meses y días para DateFormat en español (ver MyApp.build).
  await initializeDateFormatting();
  final sharedPreferences = await SharedPreferences.getInstance();
  if (!launchedWithSession) {
    unawaited(clearHomeWidgetForSignedOutLaunch(prefs: sharedPreferences));
  }

  return _setupRiverpod(
    revenueCatService: revenueCatService,
    pushMessaging: pushMessaging,
    sharedPreferences: sharedPreferences,
    secureStorage: appSecureStorage,
    launchedWithSession: launchedWithSession,
  );
}

Future<void> _setupEnviroment() async {
  // Android: `--flavor X` (appFlavor). iOS todavía no tiene esquemas por
  // flavor, así que ahí sigue siendo `--dart-define=FLAVOR=X`.
  final flavor =
      appFlavor ??
      const String.fromEnvironment('FLAVOR', defaultValue: 'development');
  final fileName = '$_dotenvBaseFolder.env.$flavor';
  await dotenv.load(fileName: fileName);
}

Widget _setupRiverpod({
  required RevenueCatService revenueCatService,
  required PushMessaging pushMessaging,
  required SharedPreferences sharedPreferences,
  required FlutterSecureStorage secureStorage,
  required bool launchedWithSession,
}) {
  final auth = Supabase.instance.client.auth;
  // Seguridad: cada cambio de usuario descarta todo el estado de Riverpod
  // (y las cachés en disco del que se fue): otra cuenta nunca ve nada de la
  // anterior, ni por un instante. Ver SessionScope.
  return _setupEasyLocalization(
    app: SessionScope(
      initialUserId: auth.currentUser?.id,
      userIds: auth.onAuthStateChange.map((event) => event.session?.user.id),
      prefs: sharedPreferences,
      overrides: [
        revenueCatServiceProvider.overrideWithValue(revenueCatService),
        pushMessagingProvider.overrideWithValue(pushMessaging),
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        secureStorageProvider.overrideWithValue(secureStorage),
        widgetLaunchedWithSessionProvider.overrideWithValue(
          launchedWithSession,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

Widget _setupEasyLocalization({required Widget app}) {
  return EasyLocalization(
    supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],
    path: _translationsPath,
    // Teléfono en un idioma que no es español ni inglés (alemán, portugués…):
    // inglés. Un es-UY o es-AR cae igual en es-ES por el código de idioma.
    fallbackLocale: const Locale('en', 'US'),
    child: app,
  );
}

class MyApp extends HookConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(revenueCatAuthSyncProvider);
    ref.watch(pushAuthSyncProvider);
    // El idioma de la app (no el del sistema) es el de las notificaciones
    // y el de Porty.
    ref.read(pushControllerProvider.notifier).localeCode =
        context.locale.languageCode;
    AppLanguage.set(context.locale.languageCode);
    // Fechas en el idioma de la app ("5 nov 2026" / "Nov 5, 2026"). es_419
    // mantiene los montos como hoy ("\$2,058.00") en los dos idiomas: solo
    // cambian los nombres de meses y días y el orden de la fecha.
    Intl.defaultLocale = AppLanguage.isEnglish ? 'en_US' : 'es_419';
    final lightTheme = ref.watch(themeDataLightProvider);
    final darkTheme = ref.watch(themeDataDarkProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Mientras el chequeo corre (o si falla) la app arranca normal.
    final update = ref.watch(appUpdateStatusProvider).valueOrNull;
    final outfit = ref.watch(portyOutfitProvider);
    return MaterialApp.router(
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: !kReleaseMode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      title: 'app_name'.tr(),
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      builder: (context, child) {
        // Los accesorios que eligió el usuario, para todos los Porty.
        return PortyOutfitScope(
          outfit: outfit,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Theme.of(context).colorScheme.surface),
              ),
              if (child != null) child,
              if (update?.required ?? false)
                Positioned.fill(
                  child: AppUpdateRequiredScreen(storeUrl: update!.storeUrl),
                ),
            ],
          ),
        );
      },
    );
  }
}

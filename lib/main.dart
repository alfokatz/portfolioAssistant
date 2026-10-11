import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/porty_outfit/domain/porty_outfit.dart';
import 'package:portfolio_assistant/features/porty_outfit/providers/porty_outfit_provider.dart';
import 'package:portfolio_assistant/config/navigation/app_router.dart';
import 'package:portfolio_assistant/config/supabase/secure_auth_storage.dart';
import 'package:portfolio_assistant/config/supabase/supabase_initializer.dart';
import 'package:portfolio_assistant/features/app_update/app_update_gate.dart';
import 'package:portfolio_assistant/features/app_update/app_update_required_screen.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_debug_log.dart';
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

const _translationsPath = 'assets/translations';
const _dotenvBaseFolder = 'assets/env/';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  GenUiDebugLog.installLoggerBridge();
  // El primer frame es Porty (el mismo del splash nativo) mientras se
  // inicializa todo; después, la app (ver AppBootstrap).
  runApp(const AppBootstrap(initialize: _initialize));
}

/// Entorno, Supabase (restaura la sesión guardada), RevenueCat, idioma y
/// preferencias; devuelve la app lista para montar.
Future<Widget> _initialize() async {
  await _setupEnviroment();
  await SupabaseInitializer.initialize();
  final revenueCatService = await RevenueCatInitializer.initialize();
  // Sin la configuración nativa de Firebase, la app funciona sin push.
  final pushMessaging = await FirebasePushMessaging.create();
  await EasyLocalization.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();

  return _setupRiverpod(
    revenueCatService: revenueCatService,
    pushMessaging: pushMessaging,
    easyLocalization: _setupEasyLocalization(app: const MyApp()),
    sharedPreferences: sharedPreferences,
    secureStorage: appSecureStorage,
  );
}

Future<void> _setupEnviroment() async {
  final flavor = const String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'development',
  );
  final fileName = '$_dotenvBaseFolder.env.$flavor';
  await dotenv.load(fileName: fileName);
}

Widget _setupRiverpod({
  required RevenueCatService revenueCatService,
  required PushMessaging pushMessaging,
  required Widget easyLocalization,
  required SharedPreferences sharedPreferences,
  required FlutterSecureStorage secureStorage,
}) {
  return ProviderScope(
    overrides: [
      revenueCatServiceProvider.overrideWithValue(revenueCatService),
      pushMessagingProvider.overrideWithValue(pushMessaging),
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      secureStorageProvider.overrideWithValue(secureStorage),
    ],
    child: easyLocalization,
  );
}

Widget _setupEasyLocalization({required Widget app}) {
  return EasyLocalization(
    supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],
    path: _translationsPath,
    fallbackLocale: const Locale('es', 'ES'),
    child: app,
  );
}

class MyApp extends HookConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(revenueCatAuthSyncProvider);
    ref.watch(pushAuthSyncProvider);
    // El idioma de la app (no el del sistema) es el de las notificaciones.
    ref.read(pushControllerProvider.notifier).localeCode =
        context.locale.languageCode;
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

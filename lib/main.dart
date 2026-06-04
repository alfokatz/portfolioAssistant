import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show
        AndroidOptions,
        FlutterSecureStorage,
        IOSOptions,
        KeychainAccessibility;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/navigation/app_router.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/closed_position_local_data_source_impl.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/position_local_data_source_impl.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/models/closed_position_model.dart';
import 'package:portfolio_assistant/infraestructure/models/position_model.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart'
    show themeDataProvider;
import 'package:shared_preferences/shared_preferences.dart';

const _translationsPath = 'assets/translations';
const _dotenvBaseFolder = 'assets/env/';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _setupEnviroment();
  await EasyLocalization.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(PositionModelAdapter());
  Hive.registerAdapter(ClosedPositionModelAdapter());
  final positionsBox = await Hive.openBox<PositionModel>('positions');
  final closedPositionsBox =
      await Hive.openBox<ClosedPositionModel>('closed_positions');
  final sharedPreferences = await SharedPreferences.getInstance();

  runApp(
    _setupRiverpod(
      easyLocalization: _setupEasyLocalization(app: const MyApp()),
      sharedPreferences: sharedPreferences,
      secureStorage: const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      ),
      positionsBox: positionsBox,
      closedPositionsBox: closedPositionsBox,
    ),
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
  required Widget easyLocalization,
  required SharedPreferences sharedPreferences,
  required FlutterSecureStorage secureStorage,
  required Box<PositionModel> positionsBox,
  required Box<ClosedPositionModel> closedPositionsBox,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      secureStorageProvider.overrideWithValue(secureStorage),
      positionsBoxProvider.overrideWithValue(positionsBox),
      closedPositionsBoxProvider.overrideWithValue(closedPositionsBox),
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
    final theme = ref.watch(themeDataProvider);
    return MaterialApp.router(
      routerConfig: ref.watch(appRouterProvider).getRouter(),
      debugShowCheckedModeBanner: !kReleaseMode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      title: 'title'.tr(),
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
    );
  }
}

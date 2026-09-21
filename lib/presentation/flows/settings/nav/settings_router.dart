import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/config/navigation/fade_scale_page.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/settings_screen.dart';

class SettingsRouter {
  static const String settingsRouteName = 'Settings';

  static GoRoute getRoute() {
    return GoRoute(
      name: settingsRouteName,
      path: 'Settings',
      pageBuilder:
          (context, state) => fadeScalePage<void>(
            key: state.pageKey,
            name: settingsRouteName,
            child: const SettingsScreen(),
          ),
    );
  }
}

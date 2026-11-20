import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_screen.dart';

/// `/daily-brief`, con `extra: {day, source}` (`source`: `push` | `home` |
/// `feed`). Sin extra, abre el de hoy desde la Home.
class DailyBriefRouter {
  static const String routeName = 'DailyBrief';
  static const String path = '/daily-brief';

  /// El `extra` de la ruta.
  static Map<String, String> args({String? day, String source = 'home'}) => {
    'day': day ?? DailyBriefNumbers.dayKey(DateTime.now()),
    'source': source,
  };

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder: (context, state) {
        final extra = state.extra;
        final map = extra is Map ? extra : const {};
        return MaterialPage<void>(
          key: state.pageKey,
          child: DailyBriefScreen(
            day: map['day'] is String ? map['day'] as String : null,
            source: map['source'] is String ? map['source'] as String : 'home',
          ),
          name: routeName,
        );
      },
    );
  }
}

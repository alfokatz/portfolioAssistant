import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/weekly_report/view/weekly_report_screen.dart';

class WeeklyReportRouter {
  static const String routeName = 'WeeklyReport';
  static const String path = '/weekly-report';

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const WeeklyReportScreen(),
            name: routeName,
          ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/allocation/view/allocation_screen.dart';

/// Ruta de nivel superior: se llega desde Ajustes, desde la Home (cuando la
/// cartera se alejó del plan) y desde la notificación del lunes.
class AllocationRouter {
  static const routeName = 'Allocation';
  static const path = '/allocation';

  static GoRoute getRoute() => GoRoute(
    name: routeName,
    path: path,
    pageBuilder:
        (context, state) => MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          child: const AllocationScreen(),
        ),
  );
}

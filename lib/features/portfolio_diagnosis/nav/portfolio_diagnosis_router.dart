import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/portfolio_diagnosis_screen.dart';

/// Ruta de nivel superior (fuera del shell de tabs): se abre sola después
/// de la primera carga de la cartera y desde la entrada de la Home.
class PortfolioDiagnosisRouter {
  static const routeName = 'PortfolioDiagnosis';
  static const path = '/diagnosis';

  static GoRoute getRoute() => GoRoute(
    name: routeName,
    path: path,
    pageBuilder:
        (context, state) => MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          fullscreenDialog: true,
          child: const PortfolioDiagnosisScreen(),
        ),
  );
}

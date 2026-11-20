import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/investor_profile/view/investor_profile_screen.dart';

/// Ruta de nivel superior (fuera del shell de tabs) para poder empujarla
/// tanto desde Ajustes como desde el aviso de Porty en el chat: "atrás"
/// vuelve a donde estaba el usuario, sin cambiar de tab.
class InvestorProfileRouter {
  static const routeName = 'InvestorProfile';
  static const path = '/investor-profile';

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            name: routeName,
            child: const InvestorProfileScreen(),
          ),
    );
  }
}

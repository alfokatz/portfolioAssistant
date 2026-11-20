import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/porty_outfit/view/porty_outfit_screen.dart';

/// Ajustes → "Personalizá a Porty". Ruta de nivel superior, como el perfil.
class PortyOutfitRouter {
  static const routeName = 'PortyOutfit';
  static const path = '/porty-outfit';

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            name: routeName,
            child: const PortyOutfitScreen(),
          ),
    );
  }
}

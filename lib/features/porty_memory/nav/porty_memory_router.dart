import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/porty_memory/view/porty_memory_screen.dart';

/// Ruta de nivel superior, como el perfil de inversor: se empuja desde
/// Ajustes y desde el "Porty anotó…" del chat, y "atrás" vuelve a donde
/// estaba el usuario.
class PortyMemoryRouter {
  static const routeName = 'PortyMemory';
  static const path = '/porty-memory';

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            name: routeName,
            child: const PortyMemoryScreen(),
          ),
    );
  }
}

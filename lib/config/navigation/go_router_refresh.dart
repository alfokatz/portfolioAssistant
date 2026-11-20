import 'dart:async';

import 'package:flutter/foundation.dart';

/// Notifica a [GoRouter] cuando cambia el estado de autenticación.
class GoRouterRefresh extends ChangeNotifier {
  GoRouterRefresh(Stream<dynamic> stream) {
    _subscription = stream.listen(
      (_) => notifyListeners(),
      // Un deep link de auth vencido llega como error del stream: sin este
      // handler sería una excepción no capturada.
      onError: (Object _) {},
    );
  }

  /// Fuerza a reevaluar los redirects (ej. cambió un provider que leen).
  void refresh() => notifyListeners();

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

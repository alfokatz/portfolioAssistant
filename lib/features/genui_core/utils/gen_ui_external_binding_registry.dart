import 'package:flutter/foundation.dart';

/// Registra callbacks de [DataModel.bindExternalState] y evita doble release.
final class GenUiExternalBindingRegistry {
  final List<VoidCallback> _releaseCallbacks = [];

  void add(VoidCallback release) => _releaseCallbacks.add(release);

  /// Desvincula del [DataModel] activo. Llamar antes de dispose del servicio GenUI.
  void releaseAll() {
    for (final release in List<VoidCallback>.from(_releaseCallbacks)) {
      release();
    }
    _releaseCallbacks.clear();
  }

  /// Limpia callbacks ya ejecutados por el dispose del DataModel.
  void detachWithoutRelease() => _releaseCallbacks.clear();
}

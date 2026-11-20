import 'package:purchases_flutter/purchases_flutter.dart' show Store;

/// Qué aviso de suscripción mostrar antes de confirmar el borrado.
enum DeletionStoreNotice {
  none,
  appStore,
  googlePlay,
  generic;

  /// Nombre de la tienda para el texto (`{store}`); `null` si no hay una
  /// puntual.
  String? get storeName => switch (this) {
    appStore => 'App Store',
    googlePlay => 'Google Play',
    _ => null,
  };

  /// Página de suscripciones de la tienda; `null` si no hay una puntual.
  Uri? get manageUrl => switch (this) {
    appStore => Uri.parse('https://apps.apple.com/account/subscriptions'),
    googlePlay => Uri.parse(
      'https://play.google.com/store/account/subscriptions',
    ),
    _ => null,
  };

  /// Reglas de compliance §6.1–6.2 para los entitlements activos (cancelados
  /// o no). `promotional` no cobra: no avisa. Tiendas mezcladas o
  /// desconocidas: aviso genérico.
  static DeletionStoreNotice fromStores(Iterable<Store> stores) {
    final charged = stores.where((s) => s != Store.promotional).toSet();
    if (charged.isEmpty) return none;
    final notices = {
      for (final s in charged)
        switch (s) {
          Store.appStore || Store.macAppStore => appStore,
          Store.playStore => googlePlay,
          _ => generic,
        },
    };
    return notices.length == 1 ? notices.first : generic;
  }
}

/// Por qué falló el borrado (el repositorio traduce el contrato de la edge
/// function `delete-account`).
sealed class AccountDeletionFailure {
  const AccountDeletionFailure();
}

/// `nothingDeleted: true`, 429 o 500 `misconfigured`: se puede reintentar.
final class DeletionNothingDeleted extends AccountDeletionFailure {
  const DeletionNothingDeleted();
}

/// `nothingDeleted: false` o sin respuesta: puede haber quedado a medias.
final class DeletionPartial extends AccountDeletionFailure {
  const DeletionPartial();
}

/// 401: la sesión venció (o el borrado ya terminó y se perdió la respuesta).
final class DeletionSessionExpired extends AccountDeletionFailure {
  const DeletionSessionExpired();
}

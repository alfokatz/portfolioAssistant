import 'package:flutter/foundation.dart';

/// Páginas legales públicas (las mismas que abren Ajustes y el login).
abstract final class LegalLinks {
  // Sitio porty-web (Cloudflare Pages) en portyassistant.com.
  static const terms = 'https://portyassistant.com/app/terminos';
  static const privacy = 'https://portyassistant.com/app/privacidad';

  /// Página pública de borrado de cuenta (la que pide Google Play).
  static const deleteAccount = 'https://portyassistant.com/borrar-cuenta';

  /// Casilla de soporte que aparece en el error del borrado de cuenta (y que
  /// tiene que ser la misma de la página web de borrado de Google Play).
  static const supportEmail = 'soporte@portyassistant.com';
}

/// Fichas de Porty en las tiendas (para "Calificar Porty").
abstract final class StoreLinks {
  static const androidPackage = 'com.portfolioassistant.app';

  /// Apple ID numérico de la app en App Store Connect (App Information →
  /// Apple ID). Vacío hasta crear la app: mientras tanto "Calificar" no se
  /// muestra en iOS.
  static const appStoreId = '';

  /// Dónde dejar una reseña en la tienda de esta plataforma, o null si
  /// todavía no hay ficha.
  static String? get rateUrl => switch (defaultTargetPlatform) {
    TargetPlatform.android =>
      'https://play.google.com/store/apps/details?id=$androidPackage',
    TargetPlatform.iOS when appStoreId.isNotEmpty =>
      'https://apps.apple.com/app/id$appStoreId?action=write-review',
    _ => null,
  };
}

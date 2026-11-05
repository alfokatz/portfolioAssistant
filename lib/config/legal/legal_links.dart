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

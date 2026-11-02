/// Páginas legales públicas (las mismas que abren Ajustes y el login).
abstract final class LegalLinks {
  static const terms = 'https://portfolioai.app/terms';
  static const privacy = 'https://portfolioai.app/privacy';

  /// Casilla de soporte que aparece en el error del borrado de cuenta (y que
  /// tiene que ser la misma de la página web de borrado de Google Play).
  // TODO(release-blocker): el usuario todavía no definió el mail de soporte.
  // Reemplazar este placeholder por la casilla real antes de publicar.
  static const supportEmail = 'soporte@PLACEHOLDER.invalid';
}

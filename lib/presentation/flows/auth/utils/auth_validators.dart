/// Validaciones de los formularios de auth. Devuelven la key de traducción
/// del error (o `null` si el valor es válido); la pantalla la traduce.
///
/// Son la primera barrera y la que da feedback inmediato: la política real
/// la impone Supabase (`minimum_password_length` y `password_requirements`
/// en `supabase/config.toml` y en el dashboard), que tiene que coincidir con
/// [AuthValidators.passwordMinLength] y [PasswordRequirement].
abstract final class AuthValidators {
  /// RFC 5321: 254 caracteres como máximo para una dirección.
  static const emailMaxLength = 254;
  static const passwordMinLength = 8;

  /// bcrypt (lo que usa Supabase) ignora lo que pase de 72 bytes: más largo
  /// daría una falsa sensación de seguridad.
  static const passwordMaxBytes = 72;
  static const fullNameMaxLength = 80;

  /// Parte local con los caracteres permitidos por RFC 5322 (sin comillas)
  /// y dominio con al menos un punto y etiquetas de hasta 63 caracteres.
  static final _emailPattern = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
  );

  /// Lo que se manda a Supabase: sin espacios y en minúsculas, para que
  /// `Ana@Mail.com` y `ana@mail.com` sean la misma cuenta.
  static String normalizeEmail(String value) => value.trim().toLowerCase();

  static String? email(String? value) {
    final email = normalizeEmail(value ?? '');
    if (email.isEmpty) return 'auth_email_required';
    if (email.length > emailMaxLength ||
        email.contains('..') ||
        email.startsWith('.') ||
        email.contains('.@') ||
        !_emailPattern.hasMatch(email)) {
      return 'auth_email_invalid';
    }
    return null;
  }

  /// Al iniciar sesión solo se pide que no esté vacía: las cuentas viejas
  /// pueden tener contraseñas de la política anterior (6 caracteres).
  static String? signInPassword(String? value) {
    if ((value ?? '').isEmpty) return 'auth_password_required';
    return null;
  }

  /// Contraseña nueva (registro o reset): la política completa.
  static String? newPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'auth_password_required';
    if (password.trim() != password) return 'auth_password_no_edge_spaces';
    for (final requirement in PasswordRequirement.values) {
      if (!requirement.isMetBy(password)) return requirement.errorKey;
    }
    if (_utf8Length(password) > passwordMaxBytes) {
      return 'auth_password_too_long';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    final confirm = value ?? '';
    if (confirm.isEmpty) return 'auth_confirm_password_required';
    if (confirm != password) return 'auth_password_mismatch';
    return null;
  }

  static String? fullName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'auth_full_name_required';
    if (name.length > fullNameMaxLength) return 'auth_full_name_too_long';
    // Sin caracteres de control (saltos de línea, etc.): el nombre se
    // muestra en la app y en los emails.
    if (RegExp(r'[\u0000-\u001F\u007F]').hasMatch(name)) {
      return 'auth_full_name_invalid';
    }
    return null;
  }

  static int _utf8Length(String value) {
    var bytes = 0;
    for (final rune in value.runes) {
      bytes += rune < 0x80
          ? 1
          : rune < 0x800
          ? 2
          : rune < 0x10000
          ? 3
          : 4;
    }
    return bytes;
  }
}

/// Requisitos de una contraseña nueva, en el orden en que se muestran. Los
/// mismos que `password_requirements = "lower_upper_letters_digits"` de
/// Supabase, más el largo mínimo.
enum PasswordRequirement {
  minLength('auth_password_req_length', 'auth_password_min_length'),
  mixedCase('auth_password_req_case', 'auth_password_needs_case'),
  digit('auth_password_req_digit', 'auth_password_needs_digit');

  const PasswordRequirement(this.labelKey, this.errorKey);

  /// Texto del checklist debajo del campo.
  final String labelKey;

  /// Error de validación cuando falta.
  final String errorKey;

  bool isMetBy(String password) => switch (this) {
    minLength => password.length >= AuthValidators.passwordMinLength,
    mixedCase =>
      RegExp('[a-z]').hasMatch(password) && RegExp('[A-Z]').hasMatch(password),
    digit => RegExp('[0-9]').hasMatch(password),
  };
}

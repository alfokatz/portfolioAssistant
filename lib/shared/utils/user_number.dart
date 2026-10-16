/// Un número que escribió el usuario: acepta "1.234,5", "1,234.5",
/// "1234.5" y "12,5". `null` si no es un número.
double? parseUserNumber(String raw) {
  var s = raw.trim().replaceAll(' ', '');
  if (s.isEmpty) return null;
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    s =
        lastComma > lastDot
            ? s.replaceAll('.', '').replaceAll(',', '.')
            : s.replaceAll(',', '');
  } else if (lastComma >= 0) {
    s = s.replaceAll(',', '.');
  }
  return double.tryParse(s);
}

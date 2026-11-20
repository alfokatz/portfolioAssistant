enum PasswordStrength { weak, medium, strong }

abstract final class PasswordStrengthEvaluator {
  static int score(String password) {
    if (password.isEmpty) return 0;

    var score = 0;
    if (password.length >= 8) score++;
    if (RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[A-Z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/]').hasMatch(password)) {
      score++;
    }
    return score.clamp(0, 4);
  }

  static PasswordStrength level(String password) {
    final value = score(password);
    if (value <= 1) return PasswordStrength.weak;
    if (value <= 3) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }
}

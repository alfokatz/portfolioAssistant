import 'package:clock/clock.dart';

/// Freno local contra la fuerza bruta: después de [freeAttempts] fallos
/// seguidos de credenciales, bloquea el envío un rato que se duplica con cada
/// fallo nuevo (30 s, 1 min, 2 min… hasta [maxLockout]).
///
/// Es una capa de UX y de costo para un ataque desde la app; el límite real
/// es el rate limit de Supabase (`[auth.rate_limit]`), que aplica por IP
/// aunque se salteen la app.
class LoginAttemptLimiter {
  LoginAttemptLimiter({
    this.freeAttempts = 5,
    this.baseLockout = const Duration(seconds: 30),
    this.maxLockout = const Duration(minutes: 15),
    DateTime Function()? now,
  }) : _now = now ?? clock.now;

  final int freeAttempts;
  final Duration baseLockout;
  final Duration maxLockout;
  final DateTime Function() _now;

  int _failures = 0;
  DateTime? _lockedUntil;

  /// Hasta cuándo está bloqueado, o `null` si se puede intentar.
  DateTime? get lockedUntil {
    final until = _lockedUntil;
    if (until == null || !_now().isBefore(until)) return null;
    return until;
  }

  bool get isLocked => lockedUntil != null;

  /// Registra un fallo de credenciales y devuelve hasta cuándo queda
  /// bloqueado (o `null` si todavía tiene intentos libres).
  DateTime? registerFailure() {
    _failures++;
    final over = _failures - freeAttempts;
    if (over < 0) return null;
    // 2^over, sin pasarse de maxLockout (y sin desbordar el shift).
    final factor = 1 << over.clamp(0, 20);
    final lockout = baseLockout * factor;
    _lockedUntil = _now().add(lockout > maxLockout ? maxLockout : lockout);
    return _lockedUntil;
  }

  /// Entró: se olvidan los fallos.
  void reset() {
    _failures = 0;
    _lockedUntil = null;
  }
}

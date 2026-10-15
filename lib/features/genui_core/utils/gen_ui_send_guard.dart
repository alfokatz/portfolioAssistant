/// Evita dos envíos simultáneos al mismo flujo GenUI.
///
/// [tryAcquire] es sincrónico y debe llamarse antes de cualquier `await` en
/// el flujo de envío: si el chequeo y la toma del lock quedan separados por
/// un `await`, dos envíos concurrentes pueden pasar ambos el chequeo.
final class GenUiSendGuard {
  bool _inFlight = false;

  bool get isInFlight => _inFlight;

  /// Intenta tomar el lock de forma sincrónica.
  /// Devuelve `false` si ya hay un envío en curso.
  bool tryAcquire() {
    if (_inFlight) return false;
    _inFlight = true;
    return true;
  }

  void release() {
    _inFlight = false;
  }
}

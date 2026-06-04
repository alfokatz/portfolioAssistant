/// Evita dos envíos simultáneos al mismo flujo GenUI.
final class GenUiSendGuard {
  bool _inFlight = false;

  bool get isInFlight => _inFlight;

  Future<void> run(Future<void> Function() action) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await action();
    } finally {
      _inFlight = false;
    }
  }
}

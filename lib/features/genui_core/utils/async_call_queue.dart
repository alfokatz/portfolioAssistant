/// Serializa llamadas async sobre un mismo recurso: cada [run] espera a
/// que la anterior termine (éxito o falla) antes de arrancar la suya.
///
/// Pensado para un recurso con estado mutable compartido entre llamadas
/// (ver `OpenAIGenUiService`, cuyo `history` y surfaceId resuelto por turno
/// se corrompían si dos `handleSend` corrían en paralelo sobre el mismo
/// servicio) — sin esto, un guard del lado del caller que solo bloquea
/// mientras ESE caller espera (ver `GenUiSendGuard`) no alcanza: si el
/// caller deja de esperar (p. ej. por un timeout externo) sin que el
/// trabajo real de abajo se cancele — los `Future` de Dart no son
/// cancelables — un segundo `run` puede terminar ejecutándose en paralelo
/// al primero igual.
///
/// Una falla en una llamada NUNCA bloquea a las que están esperando detrás
/// de ella en la cola — pero SÍ se propaga normalmente a quien hizo esa
/// llamada en particular, vía el `Future` que devuelve [run].
class AsyncCallQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final previous = _tail;
    final result = previous.catchError((_) {}).then((_) => operation());
    _tail = result.then((_) {}).catchError((_) {});
    return result;
  }
}

/// Corre [task] para cada elemento de [items] con a lo sumo [limit] en vuelo
/// a la vez y devuelve los resultados en el mismo orden que [items].
///
/// Para pedir cotizaciones de una cartera entera: en fila tarda la suma de
/// todas (con 10 tickers, ~10 s); todas juntas de golpe arriesgan un 429 del
/// proveedor. Con un tope chico tarda lo que las más lentas.
Future<List<R>> mapWithConcurrency<T, R>(
  List<T> items,
  Future<R> Function(T item) task, {
  int limit = 6,
}) async {
  assert(limit > 0);
  final results = List<R?>.filled(items.length, null);
  var next = 0;

  Future<void> worker() async {
    while (next < items.length) {
      final index = next++;
      results[index] = await task(items[index]);
    }
  }

  final workers = items.length < limit ? items.length : limit;
  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  return results.cast<R>();
}

/// Cache en memoria con vencimiento. Las keys de Finnhub las comparten
/// todos los usuarios de la app (60 req/min en total), así que un dato que
/// no cambia minuto a minuto (fundamentals, calendario de resultados) no
/// debería pedirse de nuevo en cada turno.
class TtlCache<V> {
  TtlCache(this.ttl, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;
  final _entries = <String, ({DateTime at, V value})>{};

  V? get(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (_clock().difference(entry.at) > ttl) {
      _entries.remove(key);
      return null;
    }
    return entry.value;
  }

  void put(String key, V value) => _entries[key] = (at: _clock(), value: value);
}

/// JSON que no puede fallar: `jsonEncode` tira con `NaN` o infinito, y un
/// número así (una meta sin plazo, un precio en 0) no puede dejar el widget
/// sin escribir. Los números no finitos pasan a `null`, en mapas y listas.
Object? widgetJsonSafe(Object? value) {
  if (value is double) return value.isFinite ? value : null;
  if (value is Map) {
    return {
      for (final e in value.entries) e.key.toString(): widgetJsonSafe(e.value),
    };
  }
  if (value is List) return [for (final v in value) widgetJsonSafe(v)];
  return value;
}

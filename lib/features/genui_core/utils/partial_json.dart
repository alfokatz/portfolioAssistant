import 'dart:convert';

/// Lee JSON que todavía se está escribiendo (una respuesta en streaming):
/// los valores de primer nivel ya completos, y el último a medias cerrado
/// de la forma más prudente posible — un string abierto se cierra donde
/// está, y lo que no llega a ser válido (una clave sin valor, un número o
/// literal cortado) se descarta.
///
/// Solo sirve para mostrar una vista previa: el resultado final siempre se
/// procesa entero, por el camino de siempre.
abstract final class PartialJson {
  /// Cuántas veces se recorta hacia atrás buscando un corte válido.
  static const _maxCuts = 12;

  /// Los objetos y listas de primer nivel de [text] (lo que haya fuera de
  /// ellos, como cercos de markdown o texto suelto, se ignora).
  static List<Object?> values(String text) {
    final out = <Object?>[];
    var depth = 0;
    var inString = false;
    var escaped = false;
    var start = -1;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (depth == 0) {
        if (c == '{' || c == '[') {
          start = i;
          depth = 1;
        }
        continue;
      }
      switch (c) {
        case '"':
          inString = true;
        case '{' || '[':
          depth++;
        case '}' || ']':
          depth--;
          if (depth == 0) {
            try {
              out.add(jsonDecode(text.substring(start, i + 1)));
            } catch (_) {
              // un valor roto: se saltea
            }
            start = -1;
          }
      }
    }
    if (start >= 0) {
      final partial = complete(text.substring(start));
      if (partial != null) out.add(partial);
    }
    return out;
  }

  /// [prefix] (que empieza con `{` o `[`) cerrado y decodificado, o `null`
  /// si no hay ningún corte válido.
  static Object? complete(String prefix) {
    final scan = _Scan(prefix);
    // Primero, tal como está (con el string abierto cerrado ahí mismo): es
    // lo que deja ver el texto mientras se escribe.
    final candidates = <String>[
      if (scan.endsInString) scan.closedString,
      for (final cut in scan.cuts.reversed.take(_maxCuts)) cut.render(prefix),
    ];
    for (final candidate in candidates) {
      try {
        return jsonDecode(candidate);
      } catch (_) {
        // probar el corte anterior
      }
    }
    return null;
  }
}

/// Un recorrido de [text] que anota dónde se puede cortar y con qué
/// cierres (`}`/`]`) queda válido cada corte.
class _Scan {
  _Scan(String text) {
    final stack = <String>[];
    var inString = false;
    var escaped = false;
    var stringStart = -1;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
          _cut(i + 1, stack);
        }
        continue;
      }
      switch (c) {
        case '"':
          inString = true;
          stringStart = i;
        case '{':
          stack.add('}');
          _cut(i + 1, stack);
        case '[':
          stack.add(']');
          _cut(i + 1, stack);
        case '}' || ']':
          if (stack.isNotEmpty) stack.removeLast();
          _cut(i + 1, stack);
      }
    }
    endsInString = inString;
    if (inString) {
      var body = text;
      // Un escape a medias ("\" o "\u00") no se puede cerrar: afuera.
      final partialEscape = RegExp(r'\\(u[0-9a-fA-F]{0,3})?$');
      final match = partialEscape.firstMatch(body);
      if (match != null && _isOpenEscape(body, match.start)) {
        body = body.substring(0, match.start);
      }
      closedString =
          body.length > stringStart ? '$body"${_closers(stack)}' : '';
    }
  }

  late final bool endsInString;
  String closedString = '';
  final cuts = <_Cut>[];

  void _cut(int end, List<String> stack) =>
      cuts.add(_Cut(end, _closers(stack)));

  static String _closers(List<String> stack) => stack.reversed.join();

  /// Si la barra en [index] abre un escape (no es la segunda de `\\`).
  static bool _isOpenEscape(String text, int index) {
    var slashes = 0;
    for (var i = index; i >= 0 && text[i] == r'\'; i--) {
      slashes++;
    }
    return slashes.isOdd;
  }
}

/// Un corte posible: el texto hasta [end] más los cierres pendientes.
class _Cut {
  const _Cut(this.end, this.closers);

  final int end;
  final String closers;

  String render(String text) {
    var body = text.substring(0, end).trimRight();
    if (body.endsWith(',')) body = body.substring(0, body.length - 1);
    return '$body$closers';
  }
}

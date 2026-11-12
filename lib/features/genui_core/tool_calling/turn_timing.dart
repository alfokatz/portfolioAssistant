import 'dart:convert';

/// Cuánto tardó cada tramo de un turno del chat, para el evento
/// `chat_turn_timing` (ver docs/superpowers/research/2026-10-15-porty-latencia.md,
/// §4). Solo duraciones, nombres de tools, estados y contadores: nunca el
/// texto de la pregunta, tickers ni argumentos.
///
/// Todos los tiempos son ms desde que el usuario mandó la pregunta.
class TurnTiming {
  TurnTiming({Stopwatch? clock}) : _clock = (clock ?? Stopwatch())..start();

  final Stopwatch _clock;
  final rounds = <TimedRound>[];
  final tools = <TimedTool>[];

  /// Espera de [OpenAiRequestThrottle] antes del primer pedido.
  int throttleMs = 0;

  /// Primer texto de la respuesta en pantalla (solo con streaming).
  int? firstTextMs;

  /// La respuesta completa quedó en pantalla.
  int? readyMs;

  /// Por qué hubo una ronda más: `grounding` (faltaban datos), `rewrite`
  /// (el texto no pasó el control), `needs_retry` (una tool pidió otra
  /// llamada).
  String? extraRound;

  /// Pedidos repetidos: 429 de OpenAI y reintentos de la ronda final.
  int retries = 0;

  bool streaming = false;

  /// Largo de la respuesta final (caracteres de A2UI): lo que más pesa en
  /// la ronda final.
  int finalChars = 0;

  /// `x-porty-region` del proxy: dónde corrió la función.
  String? region;

  int get elapsedMs => _clock.elapsedMilliseconds;

  /// Hasta el primer pedido al modelo: lo que la app hace antes (cargas,
  /// armado del contexto, throttle).
  int? get preMs => rounds.isEmpty ? null : rounds.first.startMs;

  TimedRound startRound() {
    final round = TimedRound(elapsedMs);
    rounds.add(round);
    return round;
  }

  void endRound(TimedRound round, String kind) {
    round
      ..endMs = elapsedMs
      ..kind = kind;
  }

  /// Lo que devolvió el proxy en `Server-Timing` para la ronda en curso
  /// (`auth;dur=12, begin;dur=40, …`).
  void serverTiming(String header, String? region) {
    if (region != null && region.isNotEmpty) this.region = region;
    if (rounds.isEmpty) return;
    rounds.last.server = parseServerTiming(header);
  }

  void textSeen() => firstTextMs ??= elapsedMs;

  void ready() => readyMs ??= elapsedMs;

  /// Props del evento. [result]: cómo terminó el turno (`answered`,
  /// `quota`, `paywall`, `timeout`, `failed`…).
  Map<String, Object?> toProps({required String result}) {
    Map<String, Object?> build({required bool withServer}) => {
      'v': 1,
      'result': result,
      'stream': streaming,
      'total_ms': elapsedMs,
      if (preMs != null) 'pre_ms': preMs,
      if (throttleMs > 0) 'throttle_ms': throttleMs,
      if (firstTextMs != null) 'first_text_ms': firstTextMs,
      if (readyMs != null) 'ready_ms': readyMs,
      'round_count': rounds.length,
      'rounds': [
        for (final r in rounds.take(_maxItems))
          r.toJson(withServer: withServer),
      ],
      'tools': [for (final t in tools.take(_maxItems)) t.toJson()],
      if (extraRound != null) 'extra_round': extraRound,
      if (retries > 0) 'retries': retries,
      if (finalChars > 0) 'final_chars': finalChars,
      if (region != null) 'region': region,
    };
    final full = build(withServer: true);
    // `product_events.props` acepta hasta 2 KB de `pg_column_size` (jsonb),
    // que para estos objetos chicos ocupa hasta ~1,7× el texto JSON
    // (medido: 1.530 caracteres → 2.546 bytes). Si un turno raro (muchas
    // rondas) se pasa, se sacan los tramos del proxy, no el evento: sin
    // ellos, el peor caso (8 rondas y 8 tools) son 1.786 bytes.
    return jsonEncode(full).length <= _maxPropsChars
        ? full
        : build(withServer: false);
  }

  static const _maxItems = 8;
  static const _maxPropsChars = 1150;

  /// `auth;dur=12.4, begin;dur=40` → `{auth: 12, begin: 40}`. Lo que no
  /// tenga esa forma se ignora.
  static Map<String, int> parseServerTiming(String header) {
    final out = <String, int>{};
    for (final part in header.split(',')) {
      final match = _metric.firstMatch(part.trim());
      if (match == null) continue;
      final ms = double.tryParse(match.group(2)!);
      if (ms != null) out[match.group(1)!] = ms.round();
    }
    return out;
  }

  static final _metric = RegExp(r'^([a-z_]{1,16});dur=([0-9.]+)$');
}

/// Un pedido al modelo.
class TimedRound {
  TimedRound(this.startMs);

  final int startMs;
  int? endMs;

  /// `tools` (pidió tools), `answer` (respondió), `rate_limited` (429),
  /// `failed` (error o timeout).
  String kind = 'failed';

  /// Tramos del proxy (`Server-Timing`).
  Map<String, int> server = const {};

  int? get ms => endMs == null ? null : endMs! - startMs;

  Map<String, Object?> toJson({bool withServer = true}) => {
    'kind': kind,
    'start_ms': startMs,
    if (ms != null) 'ms': ms,
    if (withServer && server.isNotEmpty) 'server': server,
  };
}

/// Una tool del turno.
class TimedTool {
  const TimedTool(this.name, this.ms, this.status);

  final String name;
  final int ms;

  /// El `status` del resultado (`ok`, `failed`, `locked`…), o `memo` si
  /// no se ejecutó porque ya se había pedido igual en el turno.
  final String status;

  Map<String, Object?> toJson() => {'name': name, 'ms': ms, 'status': status};
}

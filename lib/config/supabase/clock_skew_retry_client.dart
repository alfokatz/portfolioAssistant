import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Reintenta los requests que Supabase rechaza con `JWT issued at future`.
///
/// El JWT lo firma Auth con su reloj y lo valida PostgREST (o el gateway) con
/// el suyo; si Auth va unos segundos adelantado, un token recién renovado es
/// "del futuro" hasta que el reloj del validador lo alcanza. Pasa sobre todo
/// al arrancar (hot restart, volver de background): la sesión guardada venció,
/// se renueva y los primeros queries salen al instante con el token nuevo.
///
/// Espera lo justo (el `iat` del token contra el header `Date` de la
/// respuesta, con tope [maxWait]) y reenvía el mismo request. Solo reintenta
/// `http.Request` (body en memoria); los streamed/multipart pasan igual.
class ClockSkewRetryClient extends http.BaseClient {
  ClockSkewRetryClient({
    http.Client? inner,
    this.maxRetries = 2,
    this.maxWait = const Duration(seconds: 10),
    Future<void> Function(Duration)? delay,
  }) : _inner = inner ?? http.Client(),
       _delay = delay ?? Future<void>.delayed;

  final http.Client _inner;
  final int maxRetries;
  final Duration maxWait;
  final Future<void> Function(Duration) _delay;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) return _inner.send(request);

    var attempt = 0;
    var current = request;
    while (true) {
      final response = await _inner.send(current);
      if (response.statusCode != 401 || attempt >= maxRetries) return response;

      final bytes = await response.stream.toBytes();
      if (!_isIssuedAtFuture(bytes)) return _rebuild(response, bytes);

      attempt++;
      await _delay(_waitFor(request, response));
      current = _copy(request);
    }
  }

  static bool _isIssuedAtFuture(List<int> bytes) => utf8
      .decode(bytes, allowMalformed: true)
      .toLowerCase()
      .contains('issued at future');

  /// `iat - ahora del servidor` + 1 s (el `Date` tiene resolución de segundos);
  /// sin datos para calcularlo, 1 s.
  Duration _waitFor(http.Request request, http.StreamedResponse response) {
    const fallback = Duration(seconds: 1);
    final iat = _issuedAt(request.headers['Authorization']);
    final date = response.headers['date'];
    if (iat == null || date == null) return fallback;
    final DateTime serverNow;
    try {
      serverNow = HttpDate.parse(date);
    } catch (_) {
      return fallback;
    }
    final wait = iat.difference(serverNow) + const Duration(seconds: 1);
    if (wait < fallback) return fallback;
    return wait > maxWait ? maxWait : wait;
  }

  static DateTime? _issuedAt(String? authorization) {
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }
    final parts = authorization.substring(7).split('.');
    if (parts.length != 3) return null;
    try {
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
              as Map<String, dynamic>;
      final iat = payload['iat'];
      if (iat is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        (iat * 1000).round(),
        isUtc: true,
      );
    } catch (_) {
      return null;
    }
  }

  static http.Request _copy(http.Request request) =>
      http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection;

  static http.StreamedResponse _rebuild(
    http.StreamedResponse response,
    List<int> bytes,
  ) => http.StreamedResponse(
    http.ByteStream.fromBytes(bytes),
    response.statusCode,
    contentLength: bytes.length,
    request: response.request,
    headers: response.headers,
    isRedirect: response.isRedirect,
    persistentConnection: response.persistentConnection,
    reasonPhrase: response.reasonPhrase,
  );

  @override
  void close() => _inner.close();
}

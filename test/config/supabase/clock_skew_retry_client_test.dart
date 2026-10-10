import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfolio_assistant/config/supabase/clock_skew_retry_client.dart';

const _futureBody =
    '{"code":"PGRST303","details":null,"hint":null,"message":"JWT issued at future"}';

String _token(DateTime iat) {
  String part(Map<String, dynamic> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final payload = {'iat': iat.millisecondsSinceEpoch ~/ 1000};
  return '${part({'alg': 'HS256'})}.${part(payload)}.signature';
}

void main() {
  final serverNow = DateTime.utc(2026, 10, 6, 12);
  final url = Uri.parse('https://x.supabase.co/rest/v1/positions');

  http.Request request() =>
      http.Request('POST', url)
        ..headers['Authorization'] =
            'Bearer ${_token(serverNow.add(const Duration(seconds: 4)))}'
        ..body = '{"a":1}';

  test('reintenta tras esperar iat - Date del servidor + 1 s', () async {
    final bodies = <String>[];
    final waits = <Duration>[];
    final inner = MockClient((req) async {
      bodies.add(req.body);
      if (bodies.length == 1) {
        return http.Response(
          _futureBody,
          401,
          headers: {'date': HttpDate.format(serverNow)},
        );
      }
      return http.Response('[]', 200);
    });
    final client = ClockSkewRetryClient(
      inner: inner,
      delay: (d) async => waits.add(d),
    );

    final response = await http.Response.fromStream(
      await client.send(request()),
    );

    expect(response.statusCode, 200);
    expect(bodies, ['{"a":1}', '{"a":1}']);
    expect(waits, [const Duration(seconds: 5)]);
  });

  test('otros 401 vuelven intactos y sin reintento', () async {
    var calls = 0;
    final inner = MockClient((_) async {
      calls++;
      return http.Response('{"message":"JWT expired"}', 401);
    });
    final client = ClockSkewRetryClient(inner: inner, delay: (_) async {});

    final response = await http.Response.fromStream(
      await client.send(request()),
    );

    expect(calls, 1);
    expect(response.statusCode, 401);
    expect(response.body, '{"message":"JWT expired"}');
  });

  test('corta en maxRetries y devuelve el último 401', () async {
    var calls = 0;
    final inner = MockClient((_) async {
      calls++;
      return http.Response(_futureBody, 401);
    });
    final client = ClockSkewRetryClient(inner: inner, delay: (_) async {});

    final response = await http.Response.fromStream(
      await client.send(request()),
    );

    expect(calls, 3);
    expect(response.statusCode, 401);
    expect(response.body, _futureBody);
  });

  test('la espera tiene tope maxWait', () async {
    final waits = <Duration>[];
    var calls = 0;
    final inner = MockClient((_) async {
      calls++;
      return calls == 1
          ? http.Response(
            _futureBody,
            401,
            headers: {
              'date': HttpDate.format(
                serverNow.subtract(const Duration(minutes: 5)),
              ),
            },
          )
          : http.Response('[]', 200);
    });
    final client = ClockSkewRetryClient(
      inner: inner,
      delay: (d) async => waits.add(d),
    );

    await client.send(request());

    expect(waits, [const Duration(seconds: 10)]);
  });
}

// Repositorio del brief: RPC (Supabase con HTTP falso) y edge function
// `daily-brief` (Dio con adaptador falso). Correr:
// flutter test test/features/daily_brief/daily_brief_repository_test.dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import 'fakes/daily_brief_fakes.dart';

/// Sesión con un usuario fijo (lo único que pide el repositorio).
class _Auth implements SupabaseAuthService {
  @override
  String requireUserId() => 'user-a';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Un adaptador de Dio que responde `status` con `body` y anota el pedido.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Object? body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DailyBriefRepository _repo({
  required http.Client rest,
  required _Adapter edge,
}) => DailyBriefRepository(
  client: SupabaseClient('http://localhost', 'anon', httpClient: rest),
  authService: _Auth(),
  edge: PortyEdgeClient(
    dio: Dio(BaseOptions(validateStatus: (s) => s != null && s < 600))
      ..httpClientAdapter = edge,
    baseUrl: 'http://localhost/functions/v1',
    accessToken: () async => 'jwt',
    anonKey: 'anon',
    region: null,
  ),
);

http.Client _rpc(Map<String, Object?> byFunction, {List<String>? calls}) =>
    MockClient((request) async {
      final name = request.url.pathSegments.last;
      calls?.add('$name ${request.body}');
      final body = byFunction[name];
      if (body is Exception) throw body;
      return http.Response(
        jsonEncode(body),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });

void main() {
  final noEdge = _Adapter(200, <String, Object?>{});

  group('RPC', () {
    test('status parses enabled and pieces', () async {
      final repo = _repo(
        rest: _rpc({
          'daily_brief_status': {
            'enabled': true,
            'pieces': {'feed': false},
          },
        }),
        edge: noEdge,
      );
      final s = await repo.status();
      expect(s.enabled, isTrue);
      expect(s.piece('feed'), isFalse);
    });

    test('status never throws: a failing call means off', () async {
      final repo = _repo(
        rest: _rpc({'daily_brief_status': Exception('boom')}),
        edge: noEdge,
      );
      expect((await repo.status()).enabled, isFalse);
    });

    test('claim sends p_day and parses the state', () async {
      final calls = <String>[];
      final repo = _repo(
        rest: _rpc({
          'claim_daily_brief': {'state': 'numbers_only'},
        }, calls: calls),
        edge: noEdge,
      );
      expect(await repo.claim(briefDay), isA<BriefClaimNumbersOnly>());
      expect(calls.single, contains('"p_day":"$briefDay"'));
    });

    test('claim never throws: unavailable', () async {
      final repo = _repo(
        rest: _rpc({'claim_daily_brief': Exception('boom')}),
        edge: noEdge,
      );
      expect(await repo.claim(briefDay), isA<BriefClaimUnavailable>());
    });

    test('complete: ok, rejected and not_claimed', () async {
      Future<DailyBriefRepository> repoWith(Object? response) async =>
          _repo(rest: _rpc({'complete_daily_brief': response}), edge: noEdge);
      expect(
        await (await repoWith({'ok': true})).complete(briefDay, {'v': 1}),
        isTrue,
      );
      expect(
        await (await repoWith({
          'ok': false,
          'reason': 'invalid_payload',
        })).complete(briefDay, {'v': 1}),
        isFalse,
      );
      await expectLater(
        (await repoWith({
          'ok': false,
          'reason': 'not_claimed',
        })).complete(briefDay, {'v': 1}),
        throwsA(isA<DailyBriefNotClaimed>()),
      );
    });

    test('complete with no network is a typed failure', () async {
      final repo = _repo(
        rest: _rpc({'complete_daily_brief': Exception('boom')}),
        edge: noEdge,
      );
      await expectLater(
        repo.complete(briefDay, {'v': 1}),
        throwsA(isA<DailyBriefNetworkFailure>()),
      );
    });
  });

  group('bundle (edge function)', () {
    Future<Map<String, Object?>> call(_Adapter edge) => _repo(
      rest: _rpc({}),
      edge: edge,
    ).bundle('brief', day: briefDay, lang: 'es');

    test(
      'sends scope, lang and day with the JWT and returns the body',
      () async {
        final edge = _Adapter(200, bundleFixture('bundle_brief_full'));
        final body = await call(edge);
        expect(body['status'], 'ok');
        expect(edge.last!.uri.path, '/functions/v1/daily-brief');
        expect(edge.last!.queryParameters, {
          'scope': 'brief',
          'lang': 'es',
          'day': briefDay,
        });
        expect(edge.last!.headers['Authorization'], 'Bearer jwt');
      },
    );

    test('403 disabled is a typed disabled failure', () async {
      final edge = _Adapter(403, {
        'error': {'type': 'disabled'},
      });
      await expectLater(call(edge), throwsA(isA<DailyBriefDisabled>()));
    });

    test('429 and 500 are server failures with their type', () async {
      await expectLater(
        call(
          _Adapter(429, {
            'error': {'type': 'rate_limited'},
          }),
        ),
        throwsA(
          isA<DailyBriefServerFailure>()
              .having((f) => f.statusCode, 'status', 429)
              .having((f) => f.type, 'type', 'rate_limited'),
        ),
      );
      await expectLater(
        call(_Adapter(500, {'error': 'x'})),
        throwsA(isA<DailyBriefServerFailure>()),
      );
    });

    test('an unconfigured client is a network failure', () async {
      final repo = DailyBriefRepository(
        client: SupabaseClient('http://localhost', 'anon'),
        authService: _Auth(),
        edge: PortyEdgeClient(
          baseUrl: '',
          accessToken: () async => null,
          anonKey: null,
          region: null,
        ),
      );
      await expectLater(
        repo.bundle('brief', day: briefDay, lang: 'es'),
        throwsA(isA<DailyBriefNetworkFailure>()),
      );
    });
  });
}

// Contrato de la edge function `delete-account` (spec §3.3) -> falla tipada.
// Correr: flutter test test/features/account_deletion
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/account_deletion/data/account_deletion_repository.dart';
import 'package:portfolio_assistant/features/account_deletion/domain/account_deletion.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body, {this.fail = false});

  final int status;
  final Object? body;
  final bool fail;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    if (fail) throw DioException(requestOptions: options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AccountDeletionRepository _repo(_Adapter adapter) => AccountDeletionRepository(
  edge: PortyEdgeClient(
    dio: Dio(BaseOptions(validateStatus: (s) => s != null && s < 600))
      ..httpClientAdapter = adapter,
    baseUrl: 'https://x.test/functions/v1',
    accessToken: () async => 'jwt',
    anonKey: 'anon',
    region: '',
  ),
);

Map<String, Object?> _error(String type, {required bool nothingDeleted}) => {
  'error': {'type': type, 'message': 'm', 'nothingDeleted': nothingDeleted},
};

void main() {
  group('AccountDeletionRepository.deleteAccount', () {
    test(
      '200 deleted:true -> null, and posts confirm:true to delete-account',
      () async {
        final adapter = _Adapter(200, {'deleted': true});
        expect(await _repo(adapter).deleteAccount(), isNull);
        expect(adapter.last!.uri.path, '/functions/v1/delete-account');
        expect(adapter.last!.method, 'POST');
        expect(adapter.last!.data, {'confirm': true});
      },
    );

    test('401 -> session expired', () async {
      final f =
          await _repo(
            _Adapter(401, _error('unauthorized', nothingDeleted: true)),
          ).deleteAccount();
      expect(f, isA<DeletionSessionExpired>());
    });

    for (final (status, type) in [
      (400, 'invalid_request'),
      (429, 'rate_limited'),
      (500, 'misconfigured'),
      (500, 'delete_failed'),
    ]) {
      test(
        '$status $type with nothingDeleted:true -> nothing deleted',
        () async {
          final f =
              await _repo(
                _Adapter(status, _error(type, nothingDeleted: true)),
              ).deleteAccount();
          expect(f, isA<DeletionNothingDeleted>());
        },
      );
    }

    for (final (status, type) in [
      (502, 'upstream_unavailable'),
      (500, 'delete_failed'),
    ]) {
      test('$status $type with nothingDeleted:false -> partial', () async {
        final f =
            await _repo(
              _Adapter(status, _error(type, nothingDeleted: false)),
            ).deleteAccount();
        expect(f, isA<DeletionPartial>());
      });
    }

    test('no response (network or timeout) -> partial', () async {
      final f = await _repo(_Adapter(0, null, fail: true)).deleteAccount();
      expect(f, isA<DeletionPartial>());
    });

    test('5xx without a readable body -> partial', () async {
      final f = await _repo(_Adapter(503, null)).deleteAccount();
      expect(f, isA<DeletionPartial>());
    });

    test('200 without deleted:true -> partial', () async {
      final f = await _repo(_Adapter(200, {'ok': 1})).deleteAccount();
      expect(f, isA<DeletionPartial>());
    });

    test('with an Apple code, sends it as apple_authorization_code', () async {
      final adapter = _Adapter(200, {'deleted': true});
      expect(
        await _repo(adapter).deleteAccount(appleAuthorizationCode: 'c-1'),
        isNull,
      );
      expect(adapter.last!.data, {
        'confirm': true,
        'apple_authorization_code': 'c-1',
      });
    });
  });
}

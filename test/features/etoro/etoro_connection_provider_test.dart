import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_connection_repository.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_sync_client.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';

final _now = DateTime(2026, 10, 9, 12);

EtoroImportResult _result({int imported = 3}) => EtoroImportResult.fromJson({
  'imported': imported,
  'closedImported': 1,
  'notImported': [
    {'ticker': 'AAPL', 'name': 'Apple', 'reason': 'leveraged', 'count': 2},
  ],
  'closedNotImported': [],
  'possibleDuplicates': ['AAPL'],
  'syncedAt': _now.toUtc().toIso8601String(),
});

/// Repositorio en memoria: simula la tabla `etoro_connections` y la edge
/// function sin red.
class _FakeRepository implements EtoroConnectionRepository {
  EtoroConnection connection = EtoroConnection.notConnected;
  EtoroSyncException? syncError;
  EtoroConnection? connectionAfterSyncError;
  bool throttled = false;
  int syncCalls = 0;
  final disconnects = <bool>[];

  @override
  Future<EtoroConnection> load() async => connection;

  @override
  Future<Uri> startConnect() async => Uri.parse('https://www.etoro.com/sso?state=s');

  @override
  Future<({EtoroImportResult result, bool throttled})> sync() async {
    syncCalls++;
    final error = syncError;
    if (error != null) {
      if (connectionAfterSyncError != null) connection = connectionAfterSyncError!;
      throw error;
    }
    connection = EtoroConnection(
      status: EtoroConnectionStatus.connected,
      lastSyncAt: _now,
      lastResult: _result(),
    );
    return (result: _result(), throttled: throttled);
  }

  @override
  Future<void> disconnect({required bool keepAsManual}) async {
    disconnects.add(keepAsManual);
    connection = EtoroConnection.notConnected;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// El navegador del sistema: devuelve el deep link que mandaría la edge
/// function (o null si el usuario lo cerró).
class _FakeLauncher implements EtoroAuthLauncher {
  _FakeLauncher(this.callback, {this.onAuthenticate});
  final Uri? callback;
  final void Function()? onAuthenticate;
  Uri? opened;

  @override
  Future<Uri?> authenticate(Uri url) async {
    opened = url;
    onAuthenticate?.call();
    return callback;
  }
}

EtoroConnectionNotifier _notifier(_FakeRepository repo, _FakeLauncher launcher) =>
    EtoroConnectionNotifier(repository: repo, launcher: launcher, clock: () => _now);

void main() {
  group('conectar', () {
    test('ok: abre eToro en el navegador, lee la conexión y avisa a la Home', () async {
      final repo = _FakeRepository();
      final launcher = _FakeLauncher(
        Uri.parse('porty-etoro://callback?status=ok'),
        // Para cuando vuelve el deep link, el servidor ya importó.
        onAuthenticate: () => repo.connection = EtoroConnection(
          status: EtoroConnectionStatus.connected,
          lastSyncAt: _now,
          lastResult: _result(imported: 25),
        ),
      );
      final n = _notifier(repo, launcher);

      final outcome = await n.connect();

      expect(launcher.opened!.host, 'www.etoro.com');
      expect(outcome, isA<EtoroConnected>());
      expect((outcome as EtoroConnected).result!.imported, 25);
      expect(outcome.syncFailed, isFalse);
      expect(n.state.connection.isConnected, isTrue);
      expect(n.state.importRevision, 1);
      expect(n.state.activity, EtoroActivity.idle);
    });

    test('conectada pero la primera importación falló → connected + syncFailed', () async {
      final repo = _FakeRepository();
      final n = _notifier(
        repo,
        _FakeLauncher(
          Uri.parse('porty-etoro://callback?status=sync_error&reason=etoro_unavailable'),
          onAuthenticate: () => repo.connection = const EtoroConnection(
            status: EtoroConnectionStatus.connected,
          ),
        ),
      );
      final outcome = await n.connect();
      expect(outcome, isA<EtoroConnected>());
      expect((outcome as EtoroConnected).syncFailed, isTrue);
      expect(outcome.result, isNull);
    });

    test('el usuario cerró el navegador → cancelado, sin cambios', () async {
      final repo = _FakeRepository();
      final n = _notifier(repo, _FakeLauncher(null));
      expect(await n.connect(), isA<EtoroConnectCancelled>());
      expect(n.state.connection.status, EtoroConnectionStatus.notConnected);
      expect(n.state.importRevision, 0);
      expect(n.state.activity, EtoroActivity.idle);
    });

    test('eToro concedió permisos de operar → falla con write_scope', () async {
      final n = _notifier(
        _FakeRepository(),
        _FakeLauncher(Uri.parse('porty-etoro://callback?status=error&reason=write_scope')),
      );
      final outcome = await n.connect();
      expect(outcome, isA<EtoroConnectFailed>());
      expect((outcome as EtoroConnectFailed).reason, 'write_scope');
      expect(n.state.connection.isConnected, isFalse);
    });

    test('plan Free → plan requerido (paywall)', () async {
      final n = _notifier(
        _FakeRepository(),
        _FakeLauncher(Uri.parse('porty-etoro://callback?status=error&reason=plan_required')),
      );
      expect(await n.connect(), isA<EtoroConnectPlanRequired>());
    });
  });

  group('sincronizar', () {
    _FakeRepository connected({DateTime? lastSyncAt}) => _FakeRepository()
      ..connection = EtoroConnection(
        status: EtoroConnectionStatus.connected,
        lastSyncAt: lastSyncAt,
        lastResult: _result(),
      );

    test('al abrir la app: sincroniza solo si lo último es viejo (15 min)', () async {
      final fresh = connected(lastSyncAt: _now.subtract(const Duration(minutes: 5)));
      final n1 = _notifier(fresh, _FakeLauncher(null));
      expect(await n1.syncIfStale(), isFalse);
      expect(fresh.syncCalls, 0);

      final stale = connected(lastSyncAt: _now.subtract(const Duration(minutes: 20)));
      final n2 = _notifier(stale, _FakeLauncher(null));
      expect(await n2.syncIfStale(), isTrue);
      expect(stale.syncCalls, 1);
      expect(n2.state.importRevision, 1);
    });

    test('sin cuenta conectada no se le pide nada a eToro', () async {
      final repo = _FakeRepository();
      final n = _notifier(repo, _FakeLauncher(null));
      expect(await n.syncIfStale(), isFalse);
      expect(await n.sync(userInitiated: true), isFalse);
      expect(repo.syncCalls, 0);
    });

    test('throttled por el servidor → no hay datos nuevos (la Home no recarga)', () async {
      final repo = connected()..throttled = true;
      final n = _notifier(repo, _FakeLauncher(null));
      await n.load();
      expect(await n.sync(), isFalse);
      expect(n.state.importRevision, 0);
    });

    test('token vencido/revocado desde eToro → "Reconectá tu cuenta", sin error suelto', () async {
      final repo = connected(lastSyncAt: _now.subtract(const Duration(hours: 2)))
        ..syncError = const EtoroSyncException('etoro_reconnect_required')
        ..connectionAfterSyncError = EtoroConnection(
          status: EtoroConnectionStatus.reconnectRequired,
          lastSyncAt: _now.subtract(const Duration(hours: 2)),
          lastResult: _result(),
        );
      final n = _notifier(repo, _FakeLauncher(null));
      await n.load();
      expect(await n.sync(userInitiated: true), isFalse);
      expect(n.state.connection.needsReconnect, isTrue);
      expect(n.state.lastActionError, isNull);
      // Lo importado sigue: la conexión conserva el último resultado.
      expect(n.state.connection.lastResult!.imported, 3);
      // Con la sesión muerta no se reintenta solo.
      expect(await n.syncIfStale(), isFalse);
      expect(repo.syncCalls, 1);
    });

    test('eToro limitó los pedidos → error para mostrar si lo pidió el usuario', () async {
      final repo = connected()
        ..syncError = const EtoroSyncException('etoro_rate_limited', retryAfterSeconds: 30);
      final n = _notifier(repo, _FakeLauncher(null));
      await n.load();
      await n.sync(userInitiated: true);
      expect(n.state.lastActionError, 'etoro_rate_limited');
      expect(n.state.activity, EtoroActivity.idle);

      // En segundo plano no ensucia la pantalla.
      n.clearError();
      await n.sync();
      expect(n.state.lastActionError, isNull);
    });
  });

  group('desconectar', () {
    for (final keep in [true, false]) {
      test('keepAsManual: $keep → se pasa al servidor y la Home recarga', () async {
        final repo = _FakeRepository()
          ..connection = const EtoroConnection(status: EtoroConnectionStatus.connected);
        final n = _notifier(repo, _FakeLauncher(null));
        await n.load();
        expect(await n.disconnect(keepAsManual: keep), isTrue);
        expect(repo.disconnects, [keep]);
        expect(n.state.connection.status, EtoroConnectionStatus.notConnected);
        expect(n.state.importRevision, 1);
      });
    }
  });

  group('lectura de la conexión', () {
    test('fromRow: estados, error y resultado', () {
      final c = EtoroConnection.fromRow({
        'status': 'reconnect_required',
        'last_sync_at': '2026-10-09T10:00:00Z',
        'last_sync_status': 'error',
        'last_error_type': 'reconnect_required',
        'last_result': {
          'imported': 2,
          'closedImported': 0,
          'notImported': [
            {'ticker': 'BTC', 'reason': 'crypto', 'count': 1},
            {'ticker': 'X', 'reason': 'algo_nuevo_del_servidor', 'count': 1},
          ],
          'possibleDuplicates': [],
        },
      });
      expect(c.needsReconnect, isTrue);
      expect(c.lastSyncFailed, isTrue);
      expect(c.lastResult!.notImported.map((i) => i.reason), [
        EtoroSkipReason.crypto,
        // Un motivo que la app no conoce no rompe nada.
        EtoroSkipReason.unknownInstrument,
      ]);
      expect(c.lastResult!.notImportedCount, 2);
      expect(EtoroConnection.fromRow({'status': 'disconnected'}).status, EtoroConnectionStatus.notConnected);
    });
  });
}

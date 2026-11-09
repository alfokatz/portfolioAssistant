import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/snaptrade/data/snaptrade_repository.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

/// Qué está haciendo la conexión ahora. Una sola acción a la vez.
enum SnaptradeActivity {
  idle,
  connecting,
  syncing,
  refreshing,
  removing,
  disconnecting,
}

class SnaptradeState {
  const SnaptradeState({
    this.loaded = false,
    this.connection = const SnaptradeConnection(),
    this.activity = SnaptradeActivity.idle,
    this.errorType,
  });

  final bool loaded;
  final SnaptradeConnection connection;
  final SnaptradeActivity activity;

  /// Abriendo el portal, sincronizando, quitando o desconectando: los
  /// botones se deshabilitan.
  bool get busy => activity != SnaptradeActivity.idle;

  bool get isSyncing => activity == SnaptradeActivity.syncing;

  /// El último error para mostrar (`SnaptradeException.type`).
  final String? errorType;

  SnaptradeState copyWith({
    bool? loaded,
    SnaptradeConnection? connection,
    SnaptradeActivity? activity,
    String? errorType,
    bool clearError = false,
  }) => SnaptradeState(
    loaded: loaded ?? this.loaded,
    connection: connection ?? this.connection,
    activity: activity ?? this.activity,
    errorType: clearError ? null : (errorType ?? this.errorType),
  );
}

/// Los brókers conectados por SnapTrade: cargar, conectar (portal),
/// sincronizar, actualizar ahora, quitar uno y desconectar todo. Cuando
/// cambia lo importado, recarga la Home.
class SnaptradeNotifier extends StateNotifier<SnaptradeState> {
  SnaptradeNotifier(
    this._repo,
    this._launcher, {
    Future<void> Function()? onImported,
  }) : _onImported = onImported,
       super(const SnaptradeState());

  final SnaptradeRepository _repo;
  final SnaptradePortalLauncher _launcher;
  final Future<void> Function()? _onImported;

  /// SnapTrade actualiza los datos una vez por día (plan Daily): pasada
  /// esta hora se vuelve a pedir lo último al abrir la app.
  static const staleAfter = Duration(hours: 1);

  Future<void> load() async {
    try {
      final connection = await _repo.load();
      if (mounted) state = state.copyWith(loaded: true, connection: connection);
    } catch (_) {
      // Sin red el cliente tira su propio error, no un SnaptradeException:
      // igual se da por leída para no dejar la pantalla esperando.
      if (mounted) state = state.copyWith(loaded: true);
    }
  }

  /// Abre el portal para conectar un bróker (o reconectar [reconnect]) y,
  /// al volver, importa. `true` si quedó al menos un bróker conectado.
  Future<bool> connect({required bool darkMode, String? reconnect}) async {
    final ok = await _run(
      SnaptradeActivity.connecting,
      reloadOnError: true,
      () async {
        final url = await _repo.portalUrl(
          darkMode: darkMode,
          reconnect: reconnect,
        );
        await _launcher.open(url);
        // Volvió (o cerró el portal): lo que haya conectado se importa igual.
        await _repo.sync(force: true);
        await load();
        await _onImported?.call();
      },
    );
    return ok && state.connection.isConnected;
  }

  /// [force]: sin el mínimo de 5 minutos del servidor (por ejemplo, recién
  /// conectó eToro directo y hay que sacarlo de acá).
  Future<void> sync({bool force = false}) async {
    if (!state.connection.isConnected) return;
    await _run(SnaptradeActivity.syncing, reloadOnError: true, () async {
      final outcome = await _repo.sync(force: force);
      await load();
      if (!outcome.throttled) await _onImported?.call();
    });
  }

  /// Al abrir la app: solo si hay algo conectado y lo último es viejo.
  Future<void> syncIfStale({DateTime? now}) async {
    if (!state.loaded) await load();
    final c = state.connection;
    if (c.status != SnaptradeStatus.connected) return;
    final last = c.lastSyncAt;
    if (last != null && (now ?? DateTime.now()).difference(last) < staleAfter) {
      return;
    }
    await sync();
  }

  /// "Actualizar ahora" (Gold). `true` si SnapTrade lo tomó: lo nuevo se ve
  /// en unos minutos, en la próxima sincronización.
  Future<bool> refresh() => _run(SnaptradeActivity.refreshing, _repo.refresh);

  /// Quita un bróker (lo importado de él se borra en la sincronización).
  Future<bool> remove(String brokerageId) =>
      _run(SnaptradeActivity.removing, reloadOnError: true, () async {
        await _repo.remove(brokerageId);
        await load();
        await _onImported?.call();
      });

  Future<bool> disconnect({required bool keepAsManual}) =>
      _run(SnaptradeActivity.disconnecting, () async {
        await _repo.disconnect(keepAsManual: keepAsManual);
        await load();
        await _onImported?.call();
      });

  /// Una acción del usuario: una a la vez, con su [activity] mientras corre
  /// y siempre de vuelta a `idle` al terminar, salga como salga. `true` si
  /// salió bien; si no, el error queda en [SnaptradeState.errorType].
  /// [reloadOnError]: releer la conexión tras un error (el servidor pudo
  /// cambiarla, p. ej. a "reconectá").
  Future<bool> _run(
    SnaptradeActivity activity,
    Future<void> Function() action, {
    bool reloadOnError = false,
  }) async {
    if (state.busy) return false;
    state = state.copyWith(activity: activity, clearError: true);
    String? error;
    try {
      await action();
    } on SnaptradeException catch (e) {
      error = e.type;
    } catch (_) {
      // Un error que el repositorio no tradujo (sin red, el portal no
      // abrió): la pantalla no puede quedar trabada.
      error = 'unavailable';
    }
    if (error != null && reloadOnError) await load();
    if (mounted) {
      state = state.copyWith(
        activity: SnaptradeActivity.idle,
        errorType: error,
      );
    }
    return error == null;
  }
}

final snaptradeProvider =
    StateNotifierProvider<SnaptradeNotifier, SnaptradeState>(
      (ref) => SnaptradeNotifier(
        ref.watch(snaptradeRepositoryProvider),
        ref.watch(snaptradePortalLauncherProvider),
        onImported: () => ref.read(homeProvider.notifier).refresh(silent: true),
      ),
    );

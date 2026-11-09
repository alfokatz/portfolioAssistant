import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/binance/data/binance_repository.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

/// Qué está haciendo la conexión ahora. Una sola acción a la vez.
enum BinanceActivity { idle, connecting, syncing, disconnecting }

class BinanceState {
  const BinanceState({
    this.loaded = false,
    this.connection = const BinanceConnection(),
    this.activity = BinanceActivity.idle,
    this.errorType,
  });

  final bool loaded;
  final BinanceConnection connection;
  final BinanceActivity activity;

  /// Conectando, sincronizando o desconectando: los botones se deshabilitan.
  bool get busy => activity != BinanceActivity.idle;

  bool get isSyncing => activity == BinanceActivity.syncing;

  /// El último error para mostrar (`BinanceException.type`).
  final String? errorType;

  BinanceState copyWith({
    bool? loaded,
    BinanceConnection? connection,
    BinanceActivity? activity,
    String? errorType,
    bool clearError = false,
  }) => BinanceState(
    loaded: loaded ?? this.loaded,
    connection: connection ?? this.connection,
    activity: activity ?? this.activity,
    errorType: clearError ? null : (errorType ?? this.errorType),
  );
}

/// La conexión con Binance: cargar, conectar, sincronizar y desconectar.
/// Cuando cambia lo importado, recarga la Home.
class BinanceNotifier extends StateNotifier<BinanceState> {
  BinanceNotifier(this._repo, {Future<void> Function()? onImported})
    : _onImported = onImported,
      super(const BinanceState());

  final BinanceRepository _repo;
  final Future<void> Function()? _onImported;

  /// Lo importado se da por viejo pasada esta hora (el servidor igual
  /// limita a una cada 5 minutos).
  static const staleAfter = Duration(minutes: 30);

  Future<void> load() async {
    try {
      final connection = await _repo.load();
      if (mounted) state = state.copyWith(loaded: true, connection: connection);
    } catch (_) {
      // Sin red el cliente tira su propio error, no un BinanceException:
      // igual se da por leída para no dejar la pantalla esperando.
      if (mounted) state = state.copyWith(loaded: true);
    }
  }

  /// `true` si quedó conectada.
  Future<bool> connect({required String apiKey, required String apiSecret}) =>
      _run(BinanceActivity.connecting, () async {
        await _repo.connect(apiKey: apiKey, apiSecret: apiSecret);
        await load();
        await _onImported?.call();
      });

  Future<void> sync() async {
    if (!state.connection.isConnected) return;
    await _run(BinanceActivity.syncing, reloadOnError: true, () async {
      final outcome = await _repo.sync();
      await load();
      if (!outcome.throttled) await _onImported?.call();
    });
  }

  /// Al abrir la app: solo si está conectada y lo último es viejo.
  Future<void> syncIfStale({DateTime? now}) async {
    if (!state.loaded) await load();
    final c = state.connection;
    if (c.status != BinanceStatus.connected) return;
    final last = c.lastSyncAt;
    if (last != null && (now ?? DateTime.now()).difference(last) < staleAfter) {
      return;
    }
    await sync();
  }

  Future<bool> disconnect({required bool keepAsManual}) =>
      _run(BinanceActivity.disconnecting, () async {
        await _repo.disconnect(keepAsManual: keepAsManual);
        await load();
        await _onImported?.call();
      });

  /// Una acción del usuario: una a la vez, con su [activity] mientras corre
  /// y siempre de vuelta a `idle` al terminar, salga como salga. `true` si
  /// salió bien; si no, el error queda en [BinanceState.errorType].
  /// [reloadOnError]: releer la conexión tras un error (el servidor pudo
  /// cambiarla, p. ej. a "reconectá").
  Future<bool> _run(
    BinanceActivity activity,
    Future<void> Function() action, {
    bool reloadOnError = false,
  }) async {
    if (state.busy) return false;
    state = state.copyWith(activity: activity, clearError: true);
    String? error;
    try {
      await action();
    } on BinanceException catch (e) {
      error = e.type;
    } catch (_) {
      // Un error que el repositorio no tradujo (sin red, respuesta rara):
      // la pantalla no puede quedar trabada en "conectando".
      error = 'unavailable';
    }
    if (error != null && reloadOnError) await load();
    if (mounted) {
      state = state.copyWith(activity: BinanceActivity.idle, errorType: error);
    }
    return error == null;
  }
}

final binanceProvider = StateNotifierProvider<BinanceNotifier, BinanceState>(
  (ref) => BinanceNotifier(
    ref.watch(binanceRepositoryProvider),
    onImported: () => ref.read(homeProvider.notifier).refresh(silent: true),
  ),
);

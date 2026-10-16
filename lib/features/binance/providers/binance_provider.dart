import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/binance/data/binance_repository.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class BinanceState {
  const BinanceState({
    this.loaded = false,
    this.connection = const BinanceConnection(),
    this.busy = false,
    this.errorType,
  });

  final bool loaded;
  final BinanceConnection connection;

  /// Conectando, sincronizando o desconectando.
  final bool busy;

  /// El último error para mostrar (`BinanceException.type`).
  final String? errorType;

  BinanceState copyWith({
    bool? loaded,
    BinanceConnection? connection,
    bool? busy,
    String? errorType,
    bool clearError = false,
  }) => BinanceState(
    loaded: loaded ?? this.loaded,
    connection: connection ?? this.connection,
    busy: busy ?? this.busy,
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
    } on BinanceException {
      if (mounted) state = state.copyWith(loaded: true);
    }
  }

  /// `true` si quedó conectada.
  Future<bool> connect({
    required String apiKey,
    required String apiSecret,
  }) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _repo.connect(apiKey: apiKey, apiSecret: apiSecret);
      await load();
      await _onImported?.call();
      if (mounted) state = state.copyWith(busy: false);
      return true;
    } on BinanceException catch (e) {
      if (mounted) state = state.copyWith(busy: false, errorType: e.type);
      return false;
    }
  }

  Future<void> sync() async {
    if (state.busy || !state.connection.isConnected) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final outcome = await _repo.sync();
      await load();
      if (!outcome.throttled) await _onImported?.call();
      if (mounted) state = state.copyWith(busy: false);
    } on BinanceException catch (e) {
      await load();
      if (mounted) state = state.copyWith(busy: false, errorType: e.type);
    }
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

  Future<bool> disconnect({required bool keepAsManual}) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _repo.disconnect(keepAsManual: keepAsManual);
      await load();
      await _onImported?.call();
      if (mounted) state = state.copyWith(busy: false);
      return true;
    } on BinanceException catch (e) {
      if (mounted) state = state.copyWith(busy: false, errorType: e.type);
      return false;
    }
  }
}

final binanceProvider = StateNotifierProvider<BinanceNotifier, BinanceState>(
  (ref) => BinanceNotifier(
    ref.watch(binanceRepositoryProvider),
    onImported: () => ref.read(homeProvider.notifier).refresh(silent: true),
  ),
);

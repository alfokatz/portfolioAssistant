import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/snaptrade/data/snaptrade_repository.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class SnaptradeState {
  const SnaptradeState({
    this.loaded = false,
    this.connection = const SnaptradeConnection(),
    this.busy = false,
    this.errorType,
  });

  final bool loaded;
  final SnaptradeConnection connection;

  /// Abriendo el portal, sincronizando, quitando o desconectando.
  final bool busy;

  /// El último error para mostrar (`SnaptradeException.type`).
  final String? errorType;

  SnaptradeState copyWith({
    bool? loaded,
    SnaptradeConnection? connection,
    bool? busy,
    String? errorType,
    bool clearError = false,
  }) => SnaptradeState(
    loaded: loaded ?? this.loaded,
    connection: connection ?? this.connection,
    busy: busy ?? this.busy,
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
    } on SnaptradeException {
      if (mounted) state = state.copyWith(loaded: true);
    }
  }

  /// Abre el portal para conectar un bróker (o reconectar [reconnect]) y,
  /// al volver, importa. `true` si quedó al menos un bróker conectado.
  Future<bool> connect({required bool darkMode, String? reconnect}) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final url = await _repo.portalUrl(
        darkMode: darkMode,
        reconnect: reconnect,
      );
      await _launcher.open(url);
      // Volvió (o cerró el portal): lo que haya conectado se importa igual.
      await _repo.sync(force: true);
      await load();
      await _onImported?.call();
      if (mounted) state = state.copyWith(busy: false);
      return state.connection.isConnected;
    } on SnaptradeException catch (e) {
      await load();
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
    } on SnaptradeException catch (e) {
      await load();
      if (mounted) state = state.copyWith(busy: false, errorType: e.type);
    }
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
  Future<bool> refresh() async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _repo.refresh();
      if (mounted) state = state.copyWith(busy: false);
      return true;
    } on SnaptradeException catch (e) {
      if (mounted) state = state.copyWith(busy: false, errorType: e.type);
      return false;
    }
  }

  /// Quita un bróker (lo importado de él se borra en la sincronización).
  Future<bool> remove(String brokerageId) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _repo.remove(brokerageId);
      await load();
      await _onImported?.call();
      if (mounted) state = state.copyWith(busy: false);
      return true;
    } on SnaptradeException catch (e) {
      await load();
      if (mounted) state = state.copyWith(busy: false, errorType: e.type);
      return false;
    }
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
    } on SnaptradeException catch (e) {
      if (mounted) state = state.copyWith(busy: false, errorType: e.type);
      return false;
    }
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

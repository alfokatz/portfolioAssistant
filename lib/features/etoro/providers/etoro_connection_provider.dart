import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_connection_repository.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_sync_client.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';

/// Qué está haciendo la conexión ahora.
enum EtoroActivity { idle, loading, connecting, syncing, disconnecting }

class EtoroState {
  const EtoroState({
    this.connection = EtoroConnection.notConnected,
    this.loaded = false,
    this.activity = EtoroActivity.idle,
    this.lastActionError,
    this.importRevision = 0,
  });

  final EtoroConnection connection;

  /// Ya se leyó la conexión del servidor al menos una vez.
  final bool loaded;
  final EtoroActivity activity;

  /// Error de la última acción del usuario (sync manual, desconectar), para
  /// mostrarlo en la pantalla de eToro. No incluye "reconectá": eso es
  /// [EtoroConnection.needsReconnect].
  final String? lastActionError;

  /// Sube cada vez que las posiciones importadas pudieron cambiar (sync,
  /// conexión, desconexión): la Home lo escucha para recargar.
  final int importRevision;

  bool get isSyncing => activity == EtoroActivity.syncing;
  bool get isBusy => activity != EtoroActivity.idle;

  EtoroState copyWith({
    EtoroConnection? connection,
    bool? loaded,
    EtoroActivity? activity,
    String? lastActionError,
    bool clearError = false,
    int? importRevision,
  }) {
    return EtoroState(
      connection: connection ?? this.connection,
      loaded: loaded ?? this.loaded,
      activity: activity ?? this.activity,
      lastActionError:
          clearError ? null : (lastActionError ?? this.lastActionError),
      importRevision: importRevision ?? this.importRevision,
    );
  }
}

/// Cómo terminó un intento de conexión.
sealed class EtoroConnectOutcome {
  const EtoroConnectOutcome();
}

/// Conectada. [result] es la primera importación (puede faltar si la
/// sincronización inicial falló: se reintenta sola).
final class EtoroConnected extends EtoroConnectOutcome {
  const EtoroConnected(this.result, {this.syncFailed = false});
  final EtoroImportResult? result;
  final bool syncFailed;
}

final class EtoroConnectCancelled extends EtoroConnectOutcome {
  const EtoroConnectCancelled();
}

final class EtoroConnectPlanRequired extends EtoroConnectOutcome {
  const EtoroConnectPlanRequired();
}

/// [reason]: `write_scope` (eToro pidió permisos de operar: se rechazó),
/// `expired`, `network`, `unavailable`, `failed`…
final class EtoroConnectFailed extends EtoroConnectOutcome {
  const EtoroConnectFailed(this.reason);
  final String reason;
}

class EtoroConnectionNotifier extends StateNotifier<EtoroState> {
  EtoroConnectionNotifier({
    required EtoroConnectionRepository repository,
    required EtoroAuthLauncher launcher,
    DateTime Function()? clock,
  }) : _repository = repository,
       _launcher = launcher,
       _clock = clock ?? DateTime.now,
       super(const EtoroState());

  final EtoroConnectionRepository _repository;
  final EtoroAuthLauncher _launcher;
  final DateTime Function() _clock;

  /// Al abrir la app (o volver a ella) se sincroniza si lo último tiene más
  /// que esto. El servidor igual limita a una cada 5 minutos.
  static const staleAfter = Duration(minutes: 15);

  Future<void> load() async {
    if (!state.loaded && state.activity == EtoroActivity.idle) {
      state = state.copyWith(activity: EtoroActivity.loading);
    }
    try {
      final connection = await _repository.load();
      if (!mounted) return;
      state = state.copyWith(
        connection: connection,
        loaded: true,
        activity:
            state.activity == EtoroActivity.loading
                ? EtoroActivity.idle
                : state.activity,
      );
    } catch (_) {
      if (!mounted) return;
      // Sin red: se queda lo que había. La Home sigue funcionando igual.
      state = state.copyWith(
        loaded: true,
        activity:
            state.activity == EtoroActivity.loading
                ? EtoroActivity.idle
                : state.activity,
      );
    }
  }

  /// Abre eToro en el navegador del sistema y espera la vuelta por deep link.
  Future<EtoroConnectOutcome> connect() async {
    if (state.isBusy && state.activity != EtoroActivity.loading) {
      return const EtoroConnectFailed('busy');
    }
    state = state.copyWith(activity: EtoroActivity.connecting, clearError: true);
    try {
      final url = await _repository.startConnect();
      final callback = await _launcher.authenticate(url);
      if (callback == null) return const EtoroConnectCancelled();

      final status = callback.queryParameters['status'];
      final reason = callback.queryParameters['reason'];
      switch (status) {
        case 'ok':
        case 'sync_error':
          final connection = await _repository.load();
          if (!mounted) return EtoroConnected(connection.lastResult);
          state = state.copyWith(
            connection: connection,
            loaded: true,
            importRevision: state.importRevision + 1,
          );
          return EtoroConnected(
            connection.lastResult,
            syncFailed: status == 'sync_error',
          );
        case 'cancelled':
          return const EtoroConnectCancelled();
        default:
          if (reason == 'plan_required') return const EtoroConnectPlanRequired();
          return EtoroConnectFailed(reason ?? 'failed');
      }
    } on EtoroSyncException catch (e) {
      if (e.isPlanRequired) return const EtoroConnectPlanRequired();
      return EtoroConnectFailed(e.type);
    } catch (_) {
      return const EtoroConnectFailed('failed');
    } finally {
      if (mounted) state = state.copyWith(activity: EtoroActivity.idle);
    }
  }

  /// Sincroniza si hay una conexión activa. [userInitiated]: pull-to-refresh
  /// o "Sincronizar ahora" (el error se guarda para mostrarlo). Devuelve
  /// `true` si trajo datos nuevos.
  Future<bool> sync({bool userInitiated = false}) async {
    if (!state.connection.isConnected || state.isBusy) return false;
    state = state.copyWith(activity: EtoroActivity.syncing, clearError: true);
    try {
      final outcome = await _repository.sync();
      final connection = await _repository.load();
      if (!mounted) return !outcome.throttled;
      state = state.copyWith(
        connection: connection,
        importRevision:
            outcome.throttled ? state.importRevision : state.importRevision + 1,
      );
      return !outcome.throttled;
    } on EtoroSyncException catch (e) {
      if (!mounted) return false;
      // reconnect_required / plan: el estado nuevo lo trae la tabla.
      final connection = await _repository.load().catchError(
        (_) => state.connection,
      );
      if (!mounted) return false;
      state = state.copyWith(
        connection: connection,
        lastActionError:
            userInitiated && !e.isReconnectRequired ? e.type : null,
      );
      return false;
    } catch (_) {
      if (mounted && userInitiated) {
        state = state.copyWith(lastActionError: 'failed');
      }
      return false;
    } finally {
      if (mounted) state = state.copyWith(activity: EtoroActivity.idle);
    }
  }

  /// Al abrir la app o volver a ella: carga la conexión y, si lo último es
  /// viejo, sincroniza en segundo plano.
  Future<bool> syncIfStale() async {
    await load();
    final connection = state.connection;
    if (!connection.isConnected) return false;
    final last = connection.lastSyncAt;
    if (last != null && _clock().difference(last) < staleAfter) return false;
    return sync();
  }

  /// Revoca en eToro y borra los tokens. [keepAsManual]: las importadas
  /// quedan como posiciones manuales; si no, se borran.
  Future<bool> disconnect({required bool keepAsManual}) async {
    if (state.isBusy) return false;
    state = state.copyWith(
      activity: EtoroActivity.disconnecting,
      clearError: true,
    );
    try {
      await _repository.disconnect(keepAsManual: keepAsManual);
      final connection = await _repository.load();
      if (!mounted) return true;
      state = state.copyWith(
        connection: connection,
        importRevision: state.importRevision + 1,
      );
      return true;
    } on EtoroSyncException catch (e) {
      if (mounted) state = state.copyWith(lastActionError: e.type);
      return false;
    } catch (_) {
      if (mounted) state = state.copyWith(lastActionError: 'failed');
      return false;
    } finally {
      if (mounted) state = state.copyWith(activity: EtoroActivity.idle);
    }
  }

  void clearError() {
    if (state.lastActionError != null) {
      state = state.copyWith(clearError: true);
    }
  }
}

/// Global (no autoDispose): la Home, Ajustes y el shell la comparten.
final etoroConnectionProvider =
    StateNotifierProvider<EtoroConnectionNotifier, EtoroState>(
      (ref) => EtoroConnectionNotifier(
        repository: ref.watch(etoroConnectionRepositoryProvider),
        launcher: ref.watch(etoroAuthLauncherProvider),
      ),
    );

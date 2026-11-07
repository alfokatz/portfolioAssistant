import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/porty_memory/data/user_memory_repository.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';

class UserMemoryState {
  const UserMemoryState({
    this.memories = const [],
    this.loaded = false,
    this.loadFailed = false,
  });

  /// Las más recientes primero.
  final List<UserMemory> memories;
  final bool loaded;
  final bool loadFailed;

  UserMemoryState copyWith({List<UserMemory>? memories}) => UserMemoryState(
    memories: memories ?? this.memories,
    loaded: true,
  );
}

/// Único dueño de la memoria en memoria (valga): la lee el chat en cada
/// turno, la escriben las tools de Porty y la pantalla de Ajustes.
class UserMemoryNotifier extends StateNotifier<UserMemoryState> {
  UserMemoryNotifier(this._repo) : super(const UserMemoryState());

  final UserMemoryRepository _repo;

  /// Vuelve a leer del servidor. Sin red conserva lo último conocido.
  Future<List<UserMemory>> load() async {
    try {
      final memories = await _repo.list();
      if (mounted) state = UserMemoryState(memories: memories, loaded: true);
      return memories;
    } catch (e) {
      debugPrint('[UserMemory] load: $e');
      if (mounted) {
        state = UserMemoryState(
          memories: state.memories,
          loaded: true,
          loadFailed: true,
        );
      }
      return state.memories;
    }
  }

  /// Lo de antes de un turno: si ya se cargó, no vuelve a pedirlo.
  Future<List<UserMemory>> ensureLoaded() async =>
      state.loaded && !state.loadFailed ? state.memories : load();

  /// Tira [UserMemoryFailure].
  Future<UserMemory> add(
    String content, {
    UserMemoryCategory category = UserMemoryCategory.other,
    UserMemorySource source = UserMemorySource.user,
  }) async {
    final memory = await _repo.create(
      content: content,
      category: category,
      source: source,
    );
    if (mounted) {
      state = state.copyWith(memories: [memory, ...state.memories]);
    }
    return memory;
  }

  /// Tira [UserMemoryFailure].
  Future<UserMemory> replace(
    String id,
    String content, {
    required UserMemoryCategory category,
  }) async {
    final memory = await _repo.update(id, content: content, category: category);
    if (mounted) {
      state = state.copyWith(
        memories: [memory, ...state.memories.where((m) => m.id != id)],
      );
    }
    return memory;
  }

  Future<void> remove(String id) async {
    await _repo.delete(id);
    if (mounted) {
      state = state.copyWith(
        memories: state.memories.where((m) => m.id != id).toList(),
      );
    }
  }

  Future<void> clear() async {
    await _repo.deleteAll();
    if (mounted) state = state.copyWith(memories: const []);
  }
}

final userMemoryProvider =
    StateNotifierProvider<UserMemoryNotifier, UserMemoryState>(
      (ref) => UserMemoryNotifier(ref.watch(userMemoryRepositoryProvider)),
    );

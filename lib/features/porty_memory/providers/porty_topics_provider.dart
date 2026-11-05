import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/porty_memory/data/porty_topics_repository.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/porty_topic.dart';

class PortyTopicsState {
  const PortyTopicsState({this.topics = const [], this.loaded = false});

  /// Los más recientes primero.
  final List<PortyTopic> topics;
  final bool loaded;

  /// Los de los últimos [PortyTopic.briefWindow], para el brief del chat.
  List<PortyTopic> recent(DateTime now) => [
    for (final t in topics)
      if (now.difference(t.lastAskedAt) <= PortyTopic.briefWindow) t,
  ];
}

/// De qué tickers habló el usuario con Porty. Nunca frena el chat: si algo
/// falla, queda lo que había.
class PortyTopicsNotifier extends StateNotifier<PortyTopicsState> {
  PortyTopicsNotifier(this._repo) : super(const PortyTopicsState());

  final PortyTopicsRepository _repo;

  Future<void> load() async {
    try {
      final topics = await _repo.list();
      if (mounted) state = PortyTopicsState(topics: topics, loaded: true);
    } catch (_) {
      if (mounted) {
        state = PortyTopicsState(topics: state.topics, loaded: true);
      }
    }
  }

  Future<List<PortyTopic>> ensureLoaded() async {
    if (!state.loaded) await load();
    return state.topics;
  }

  /// Registra lo de un turno y recarga. No tira.
  Future<void> record(List<PortyTopicDraft> drafts) async {
    if (drafts.isEmpty) return;
    try {
      await _repo.touch(drafts);
      await load();
    } catch (_) {}
  }

  /// Tira si no se pudo borrar (la pantalla avisa).
  Future<void> remove(String ticker) async {
    await _repo.delete(ticker);
    if (mounted) {
      state = PortyTopicsState(
        topics: state.topics.where((t) => t.ticker != ticker).toList(),
        loaded: true,
      );
    }
  }

  Future<void> clear() async {
    await _repo.deleteAll();
    if (mounted) state = const PortyTopicsState(loaded: true);
  }
}

final portyTopicsProvider =
    StateNotifierProvider<PortyTopicsNotifier, PortyTopicsState>(
      (ref) => PortyTopicsNotifier(ref.watch(portyTopicsRepositoryProvider)),
    );

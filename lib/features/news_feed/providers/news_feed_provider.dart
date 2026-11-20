import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/news_feed/data/news_feed_repository.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';

enum NewsLoadPhase { loading, loaded, failed, disabled }

/// Estado de un bloque de noticias: mientras recarga conserva lo que ya
/// tenía ([bundle]) para no parpadear.
class NewsScopeState {
  const NewsScopeState({this.phase = NewsLoadPhase.loading, this.bundle});

  final NewsLoadPhase phase;
  final NewsBundle? bundle;

  bool get loaded => phase == NewsLoadPhase.loaded || bundle != null;
  bool get failed => phase == NewsLoadPhase.failed && bundle == null;
  bool get disabled => phase == NewsLoadPhase.disabled;
}

/// Carga un bloque de `daily-brief`. El repositorio lanza fallas tipadas y
/// acá se vuelven fases: `disabled` (interruptor o pieza apagada) y `failed`.
class NewsScopeNotifier extends StateNotifier<NewsScopeState> {
  NewsScopeNotifier(this._load) : super(const NewsScopeState()) {
    load();
  }

  final Future<NewsBundle> Function() _load;
  var _epoch = 0;

  Future<void> load() async {
    final epoch = ++_epoch;
    state = NewsScopeState(phase: NewsLoadPhase.loading, bundle: state.bundle);
    try {
      final bundle = await _load();
      if (!mounted || epoch != _epoch) return;
      state = NewsScopeState(phase: NewsLoadPhase.loaded, bundle: bundle);
    } on DailyBriefDisabled {
      if (!mounted || epoch != _epoch) return;
      state = const NewsScopeState(phase: NewsLoadPhase.disabled);
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      state = NewsScopeState(phase: NewsLoadPhase.failed, bundle: state.bundle);
    }
  }
}

String? _userId(Ref ref) =>
    ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));

/// El interruptor y las piezas (`daily_brief_status`), una vez por sesión.
final newsStatusProvider = FutureProvider<DailyBriefStatus>((ref) {
  _userId(ref);
  return ref.watch(newsFeedRepositoryProvider).status();
});

/// Lo tuyo, temas y videos. Uno por sesión de usuario.
final newsFeedProvider =
    StateNotifierProvider<NewsScopeNotifier, NewsScopeState>((ref) {
      _userId(ref);
      final repo = ref.watch(newsFeedRepositoryProvider);
      return NewsScopeNotifier(() => repo.load(NewsScope.feed));
    });

/// "Mercado hoy".
final marketTodayProvider =
    StateNotifierProvider<NewsScopeNotifier, NewsScopeState>((ref) {
      _userId(ref);
      final repo = ref.watch(newsFeedRepositoryProvider);
      return NewsScopeNotifier(() => repo.load(NewsScope.market));
    });

/// El detalle de un tema (por `topic_id`).
final newsTopicProvider = StateNotifierProvider.autoDispose
    .family<NewsScopeNotifier, NewsScopeState, String>((ref, topicId) {
      final repo = ref.watch(newsFeedRepositoryProvider);
      return NewsScopeNotifier(
        () => repo.load(NewsScope.topic, topicId: topicId),
      );
    });

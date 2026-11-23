import 'dart:async';

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
  const NewsScopeState({
    this.phase = NewsLoadPhase.loading,
    this.bundle,
    this.searchGaveUp = false,
  });

  final NewsLoadPhase phase;
  final NewsBundle? bundle;

  /// Se agotaron los reintentos con el servidor todavía buscando.
  final bool searchGaveUp;

  /// Porty sigue buscando noticias (y la app sigue preguntando).
  bool get searching => (bundle?.isSearching ?? false) && !searchGaveUp;

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
  var _retries = 0;
  Timer? _retryTimer;

  /// Pide de nuevo el mismo scope (a mano: reintentar, volver a la pantalla).
  Future<void> load() {
    _retries = 0;
    return _fetch();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  /// Si el servidor dice `searching`, vuelve a pedir cada `retry_after_s`,
  /// hasta [NewsSearching.maxRetries] veces. Se corta al llegar resultado, al
  /// fallar o al salir de la pantalla (el provider es autoDispose).
  void _scheduleRetry(NewsBundle bundle) {
    final searching = bundle.searching;
    if (searching == null) return;
    if (_retries >= NewsSearching.maxRetries) {
      state = NewsScopeState(
        phase: NewsLoadPhase.loaded,
        bundle: bundle,
        searchGaveUp: true,
      );
      return;
    }
    _retries++;
    _retryTimer = Timer(searching.retryAfter, () {
      if (mounted) _fetch();
    });
  }

  Future<void> _fetch() async {
    _retryTimer?.cancel();
    final epoch = ++_epoch;
    state = NewsScopeState(phase: NewsLoadPhase.loading, bundle: state.bundle);
    try {
      final bundle = await _load();
      if (!mounted || epoch != _epoch) return;
      state = NewsScopeState(phase: NewsLoadPhase.loaded, bundle: bundle);
      _scheduleRetry(bundle);
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
    StateNotifierProvider.autoDispose<NewsScopeNotifier, NewsScopeState>((ref) {
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

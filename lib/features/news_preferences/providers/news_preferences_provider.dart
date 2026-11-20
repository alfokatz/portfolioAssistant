import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/news_preferences/data/news_preferences_repository.dart';
import 'package:portfolio_assistant/features/news_preferences/domain/news_preferences.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class NewsPreferencesState {
  const NewsPreferencesState({
    this.loaded = false,
    this.loadFailed = false,
    this.topics = const [],
    this.sources = const [],
    this.followed = const {},
    this.sourcePrefs = const {},
    this.markets = const {},
  });

  final bool loaded;
  final bool loadFailed;
  final List<NewsTopic> topics;
  final List<NewsSource> sources;

  /// Lo que el usuario cambió (`topic_id → followed`).
  final Map<String, bool> followed;
  final Map<String, SourcePreference> sourcePrefs;

  /// Mercados de la cartera (`US`, `.BA`…), para saber qué es "por defecto".
  final Set<String> markets;

  bool isDefault(NewsTopic t) => t.isDefaultFor(markets);

  /// Lo que cambió el usuario manda; si no, lo que arma el servidor.
  bool isFollowed(NewsTopic t) => followed[t.id] ?? isDefault(t);

  SourcePreference? preferenceOf(String domain) => sourcePrefs[domain];

  int get followedCount => followed.values.where((v) => v).length;

  int count(SourcePreference p) =>
      sourcePrefs.values.where((v) => v == p).length;

  NewsPreferencesState copyWith({
    bool? loaded,
    bool? loadFailed,
    Map<String, bool>? followed,
    Map<String, SourcePreference>? sourcePrefs,
  }) => NewsPreferencesState(
    loaded: loaded ?? this.loaded,
    loadFailed: loadFailed ?? this.loadFailed,
    topics: topics,
    sources: sources,
    followed: followed ?? this.followed,
    sourcePrefs: sourcePrefs ?? this.sourcePrefs,
    markets: markets,
  );
}

/// Temas que sigue y medios que prefiere o silencia. Los cambios se ven al
/// instante y, si la base los rechaza, se deshacen y la acción devuelve la
/// falla tipada para que la pantalla avise.
class NewsPreferencesNotifier extends StateNotifier<NewsPreferencesState> {
  NewsPreferencesNotifier({
    required NewsPreferencesStore store,
    required Set<String> Function() heldTickers,
    required void Function(ProductEvent, Map<String, Object?>) logEvent,
  }) : _store = store,
       _heldTickers = heldTickers,
       _logEvent = logEvent,
       super(const NewsPreferencesState());

  final NewsPreferencesStore _store;
  final Set<String> Function() _heldTickers;
  final void Function(ProductEvent, Map<String, Object?>) _logEvent;

  Future<void> load() async {
    try {
      final results = await Future.wait<Object>([
        _store.topics(),
        _store.userTopics(),
        _store.sources(),
        _store.userSources(),
      ]);
      if (!mounted) return;
      state = NewsPreferencesState(
        loaded: true,
        topics: results[0] as List<NewsTopic>,
        followed: results[1] as Map<String, bool>,
        sources: [
          for (final s in results[2] as List<NewsSource>)
            if (s.kind == 'media') s,
        ],
        sourcePrefs: results[3] as Map<String, SourcePreference>,
        markets: {for (final t in _heldTickers()) marketOfTicker(t)},
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loadFailed: true);
    }
  }

  /// Sigue o deja de seguir [topic]. `null` si salió bien.
  Future<NewsPreferencesFailure?> setTopic(
    NewsTopic topic, {
    required bool followed,
  }) async {
    // El tope de la base cuenta las filas con followed = true.
    if (followed &&
        state.followed[topic.id] != true &&
        state.followedCount >= NewsPreferencesLimits.topics) {
      return const TopicLimitReached();
    }
    final before = state.followed;
    final wasDefault = state.isDefault(topic);
    state = state.copyWith(followed: {...before, topic.id: followed});
    try {
      await _store.setTopic(topic.id, followed: followed);
      _logEvent(ProductEvent.newsTopicChanged, {
        'topic_id': topic.id,
        'followed': followed,
        'was_default': wasDefault,
      });
      return null;
    } on NewsPreferencesFailure catch (f) {
      if (mounted) state = state.copyWith(followed: before);
      return f;
    } catch (_) {
      if (mounted) state = state.copyWith(followed: before);
      return const NewsPreferencesUnavailable();
    }
  }

  /// Prefiere, silencia o deja normal ([preference] `null`) un medio.
  Future<NewsPreferencesFailure?> setSource(
    NewsSource source,
    SourcePreference? preference,
  ) async {
    if (preference != null &&
        state.preferenceOf(source.domain) != preference &&
        state.count(preference) >= NewsPreferencesLimits.sourcesPerList) {
      return const SourceLimitReached();
    }
    final before = state.sourcePrefs;
    state = state.copyWith(
      sourcePrefs: {
        for (final e in before.entries)
          if (e.key != source.domain) e.key: e.value,
        if (preference != null) source.domain: preference,
      },
    );
    try {
      await _store.setSource(source.domain, preference);
      _logEvent(ProductEvent.newsSourceChanged, {
        'domain': source.domain,
        'preference': preference?.name ?? 'none',
      });
      return null;
    } on NewsPreferencesFailure catch (f) {
      if (mounted) state = state.copyWith(sourcePrefs: before);
      return f;
    } catch (_) {
      if (mounted) state = state.copyWith(sourcePrefs: before);
      return const NewsPreferencesUnavailable();
    }
  }
}

final newsPreferencesProvider =
    StateNotifierProvider<NewsPreferencesNotifier, NewsPreferencesState>((ref) {
      ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
      return NewsPreferencesNotifier(
        store: ref.watch(newsPreferencesStoreProvider),
        heldTickers:
            () => {
              for (final v
                  in ref.read(homeProvider).summary?.valuations ?? const [])
                v.position.ticker.toUpperCase(),
            },
        logEvent:
            (event, props) => ref.read(productEventsProvider).log(event, props),
      );
    });

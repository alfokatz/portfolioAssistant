import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/news_preferences/domain/news_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

sealed class NewsPreferencesFailure implements Exception {
  const NewsPreferencesFailure();
}

/// Ya sigue 12 temas (`topic_limit_reached`).
class TopicLimitReached extends NewsPreferencesFailure {
  const TopicLimitReached();
}

/// Ya tiene 10 medios en esa lista (`source_limit_reached`).
class SourceLimitReached extends NewsPreferencesFailure {
  const SourceLimitReached();
}

/// Sin red, sin sesión o la base rechazó el cambio.
class NewsPreferencesUnavailable extends NewsPreferencesFailure {
  const NewsPreferencesUnavailable();
}

/// Lo que la pantalla de preferencias necesita de la base.
abstract class NewsPreferencesStore {
  Future<List<NewsTopic>> topics();

  /// `topic_id → followed` de lo que el usuario cambió (el resto sigue lo
  /// que arma el servidor por defecto).
  Future<Map<String, bool>> userTopics();
  Future<List<NewsSource>> sources();
  Future<Map<String, SourcePreference>> userSources();

  /// Lanza [NewsPreferencesFailure].
  Future<void> setTopic(String topicId, {required bool followed});

  /// `null` borra la preferencia. Lanza [NewsPreferencesFailure].
  Future<void> setSource(String domain, SourcePreference? preference);
}

/// PostgREST: `news_topics` y `news_source_allowlist` (lectura),
/// `user_news_topics` y `user_news_sources` (RLS: cada usuario lo suyo).
class NewsPreferencesRepository implements NewsPreferencesStore {
  NewsPreferencesRepository({
    required SupabaseClient client,
    required SupabaseAuthService authService,
  }) : _client = client,
       _auth = authService;

  final SupabaseClient _client;
  final SupabaseAuthService _auth;

  @override
  Future<List<NewsTopic>> topics() async {
    final rows = await _client
        .from('news_topics')
        .select(
          'id, kind, label_es, label_en, default_global, auto_markets, '
          'auto_asset_classes, region, sort',
        )
        .eq('enabled', true)
        .order('sort');
    return [
      for (final r in rows) NewsTopic.tryParse(r),
    ].whereType<NewsTopic>().toList();
  }

  @override
  Future<Map<String, bool>> userTopics() async {
    final rows = await _client
        .from('user_news_topics')
        .select('topic_id, followed');
    return {
      for (final r in rows)
        if (r['topic_id'] is String && r['followed'] is bool)
          r['topic_id'] as String: r['followed'] as bool,
    };
  }

  @override
  Future<List<NewsSource>> sources() async {
    final rows = await _client
        .from('news_source_allowlist')
        .select('domain, name, lang, region, kind')
        .order('name');
    return [
      for (final r in rows) NewsSource.tryParse(r),
    ].whereType<NewsSource>().toList();
  }

  @override
  Future<Map<String, SourcePreference>> userSources() async {
    final rows = await _client
        .from('user_news_sources')
        .select('domain, preference');
    return {
      for (final r in rows)
        if (r['domain'] is String &&
            SourcePreference.fromWire(r['preference']) != null)
          r['domain'] as String: SourcePreference.fromWire(r['preference'])!,
    };
  }

  @override
  Future<void> setTopic(String topicId, {required bool followed}) async {
    try {
      await _client.from('user_news_topics').upsert({
        'user_id': _auth.requireUserId(),
        'topic_id': topicId,
        'followed': followed,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      throw _failure(e);
    } catch (_) {
      throw const NewsPreferencesUnavailable();
    }
  }

  @override
  Future<void> setSource(String domain, SourcePreference? preference) async {
    try {
      final userId = _auth.requireUserId();
      if (preference == null) {
        await _client
            .from('user_news_sources')
            .delete()
            .eq('user_id', userId)
            .eq('domain', domain);
        return;
      }
      await _client.from('user_news_sources').upsert({
        'user_id': userId,
        'domain': domain,
        'preference': preference.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      throw _failure(e);
    } catch (_) {
      throw const NewsPreferencesUnavailable();
    }
  }

  /// Los topes los pone un trigger que lanza con el nombre del error.
  static NewsPreferencesFailure _failure(PostgrestException e) {
    final text = '${e.message} ${e.details} ${e.hint}';
    if (text.contains('topic_limit_reached')) return const TopicLimitReached();
    if (text.contains('source_limit_reached')) {
      return const SourceLimitReached();
    }
    return const NewsPreferencesUnavailable();
  }
}

final newsPreferencesStoreProvider = Provider<NewsPreferencesStore>(
  (ref) => NewsPreferencesRepository(
    client: ref.watch(supabaseClientProvider),
    authService: ref.watch(supabaseAuthServiceProvider),
  ),
);

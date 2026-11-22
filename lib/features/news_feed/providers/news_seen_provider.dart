import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lo último de Noticias que el usuario vio (la marca de su brief), guardado
/// por usuario en el dispositivo: otra cuenta nunca ve el estado de ésta.
///
/// Alimenta el punto de la pestaña Noticias: hay brief de un día que todavía
/// no abrió. (Las notas del feed no cuentan: traerlas solo para pintar un
/// punto sería una llamada más al arrancar.)
class NewsSeenNotifier extends StateNotifier<String?> {
  NewsSeenNotifier({required SharedPreferences? preferences, String? userId})
    : _prefs = preferences,
      _key = userId == null ? null : 'news_seen_$userId',
      super(null) {
    final key = _key;
    if (key != null) {
      try {
        state = _prefs?.getString(key);
      } catch (_) {}
    }
  }

  final SharedPreferences? _prefs;
  final String? _key;

  /// La marca del brief de un día.
  static String markerFor(String briefDay) => 'brief:$briefDay';

  /// Vio [marker] (abrió Noticias o el brief de ese día).
  void markSeen(String marker) {
    if (state == marker) return;
    state = marker;
    final key = _key;
    if (key == null) return;
    try {
      _prefs?.setString(key, marker);
    } catch (_) {}
  }
}

final newsSeenProvider = StateNotifierProvider<NewsSeenNotifier, String?>((
  ref,
) {
  final uid = ref.watch(
    authSessionProvider.select((s) => s.valueOrNull?.user.id),
  );
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPreferencesProvider);
  } catch (_) {
    prefs = null;
  }
  return NewsSeenNotifier(preferences: prefs, userId: uid);
});

/// La marca de lo más nuevo que hay (el brief de hoy, ya listo), o `null`.
final newsLatestMarkerProvider = Provider<String?>((ref) {
  final brief = ref.watch(
    dailyBriefControllerProvider.select(
      (s) => s.phase == DailyBriefPhase.ready ? s.brief?.day : null,
    ),
  );
  return brief == null ? null : NewsSeenNotifier.markerFor(brief);
});

/// ¿Hay algo nuevo sin ver en Noticias? Solo con la pestaña disponible.
final newsBadgeProvider = Provider<bool>((ref) {
  if (!ref.watch(newsFeedAvailableProvider)) return false;
  final latest = ref.watch(newsLatestMarkerProvider);
  if (latest == null) return false;
  return ref.watch(newsSeenProvider) != latest;
});

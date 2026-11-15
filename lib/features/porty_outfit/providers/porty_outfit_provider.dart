import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/porty_outfit/domain/porty_outfit.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La clave de antes, una sola para todo el teléfono: la personalización
/// sobrevivía al cierre de sesión y al borrado de cuenta.
const portyOutfitKey = 'porty_outfit';

/// La clave de [userId]: cada cuenta tiene su Porty.
String portyOutfitKeyFor(String userId) => '$portyOutfitKey:$userId';

/// Lo que tiene puesto Porty, guardado en el dispositivo POR USUARIO. Sin
/// sesión (login, onboarding) Porty va sin nada; al entrar, el de esa
/// cuenta; una cuenta nueva (también la que se crea después de borrar
/// otra) arranca sin nada. Global: lo lee `PortyOutfitScope` en la raíz.
class PortyOutfitNotifier extends StateNotifier<PortyOutfit> {
  PortyOutfitNotifier(this._prefs, this._userId)
    : super(_load(_prefs, _userId));

  final SharedPreferences _prefs;
  final String? _userId;

  static PortyOutfit _load(SharedPreferences prefs, String? userId) {
    _migrateLegacy(prefs, userId);
    if (userId == null) return PortyOutfit.none;
    return PortyOutfit.fromStorage(
      prefs.getStringList(portyOutfitKeyFor(userId)),
    );
  }

  /// La clave vieja: si al abrir la app hay sesión, era de ese usuario y
  /// pasa a su clave; sin sesión no se sabe de quién era y se descarta.
  static void _migrateLegacy(SharedPreferences prefs, String? userId) {
    final legacy = prefs.getStringList(portyOutfitKey);
    if (legacy == null) return;
    if (userId != null && !prefs.containsKey(portyOutfitKeyFor(userId))) {
      prefs.setStringList(portyOutfitKeyFor(userId), legacy);
    }
    prefs.remove(portyOutfitKey);
  }

  Future<void> wear(PortyAccessory accessory) => _set(state.wearing(accessory));

  Future<void> clearSlot(PortyOutfitSlot slot) => _set(state.without(slot));

  Future<void> clear() => _set(PortyOutfit.none);

  /// Borra lo guardado de esta cuenta (al eliminarla).
  Future<void> forget() async {
    state = PortyOutfit.none;
    final userId = _userId;
    if (userId != null) await _prefs.remove(portyOutfitKeyFor(userId));
  }

  Future<void> _set(PortyOutfit outfit) async {
    state = outfit;
    final userId = _userId;
    // Sin sesión no hay de quién guardarlo.
    if (userId == null) return;
    await _prefs.setStringList(portyOutfitKeyFor(userId), outfit.toStorage());
  }
}

/// El id del usuario con sesión (null sin sesión, o sin Supabase, como en
/// los tests). Se recalcula con cada cambio de sesión.
final portyOutfitUserIdProvider = Provider<String?>((ref) {
  try {
    ref.watch(authSessionProvider);
    return ref.read(supabaseAuthServiceProvider).currentUser?.id;
  } catch (_) {
    return null;
  }
});

final portyOutfitProvider =
    StateNotifierProvider<PortyOutfitNotifier, PortyOutfit>(
      (ref) => PortyOutfitNotifier(
        ref.watch(sharedPreferencesProvider),
        ref.watch(portyOutfitUserIdProvider),
      ),
    );

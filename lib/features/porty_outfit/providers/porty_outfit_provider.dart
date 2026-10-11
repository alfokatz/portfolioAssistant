import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/porty_outfit/domain/porty_outfit.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const portyOutfitKey = 'porty_outfit';

/// Lo que tiene puesto Porty, guardado en el dispositivo (como el tema o
/// las vibraciones). Global: lo lee `PortyOutfitScope` en la raíz de la app.
class PortyOutfitNotifier extends StateNotifier<PortyOutfit> {
  PortyOutfitNotifier(this._prefs)
    : super(PortyOutfit.fromStorage(_prefs.getStringList(portyOutfitKey)));

  final SharedPreferences _prefs;

  Future<void> toggle(PortyAccessory accessory) => _set(state.toggle(accessory));

  Future<void> clear() => _set(PortyOutfit.none);

  Future<void> _set(PortyOutfit outfit) async {
    state = outfit;
    await _prefs.setStringList(portyOutfitKey, outfit.toStorage());
  }
}

final portyOutfitProvider =
    StateNotifierProvider<PortyOutfitNotifier, PortyOutfit>(
      (ref) => PortyOutfitNotifier(ref.watch(sharedPreferencesProvider)),
    );

// Porty vestido es de cada cuenta: sin sesión va sin nada, al entrar el de
// esa cuenta, y una cuenta nueva (o la que se crea después de borrar otra)
// arranca sin nada (2026-11-14).
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/porty_outfit/domain/porty_outfit.dart';
import 'package:portfolio_assistant/features/porty_outfit/providers/porty_outfit_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  test('each account keeps its own Porty; without a session, none', () async {
    final prefs = await _prefs();
    final alice = PortyOutfitNotifier(prefs, 'alice');
    await alice.wear(PortyAccessory.beanie);
    expect(alice.state, isNot(PortyOutfit.none));

    // Cerró sesión: el login muestra a Porty sin nada.
    expect(PortyOutfitNotifier(prefs, null).state, PortyOutfit.none);
    // Otra cuenta (nueva): sin nada.
    expect(PortyOutfitNotifier(prefs, 'bob').state, PortyOutfit.none);
    // Vuelve a entrar Alice: como lo tenía.
    expect(PortyOutfitNotifier(prefs, 'alice').state, alice.state);
  });

  test('without a session nothing is saved', () async {
    final prefs = await _prefs();
    await PortyOutfitNotifier(prefs, null).wear(PortyAccessory.beanie);
    expect(prefs.getKeys(), isEmpty);
  });

  test('deleting the account forgets its Porty', () async {
    final prefs = await _prefs();
    final alice = PortyOutfitNotifier(prefs, 'alice');
    await alice.wear(PortyAccessory.beanie);
    await alice.forget();
    expect(alice.state, PortyOutfit.none);
    expect(prefs.containsKey(portyOutfitKeyFor('alice')), isFalse);
    expect(PortyOutfitNotifier(prefs, 'alice').state, PortyOutfit.none);
  });

  test('the old device-wide key goes to the user logged in when the app '
      'updates; logged out, it is dropped', () async {
    final stored = PortyOutfit.none.wearing(PortyAccessory.beanie).toStorage();

    final withSession = await _prefs({portyOutfitKey: stored});
    expect(PortyOutfitNotifier(withSession, 'alice').state.toStorage(), stored);
    expect(withSession.containsKey(portyOutfitKey), isFalse);
    expect(withSession.getStringList(portyOutfitKeyFor('alice')), stored);

    final loggedOut = await _prefs({portyOutfitKey: stored});
    expect(PortyOutfitNotifier(loggedOut, null).state, PortyOutfit.none);
    expect(loggedOut.containsKey(portyOutfitKey), isFalse);
    expect(PortyOutfitNotifier(loggedOut, 'alice').state, PortyOutfit.none);
  });
}

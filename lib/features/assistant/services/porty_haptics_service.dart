import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/shared/utils/provider_lookup.dart';
import 'package:shared_preferences/shared_preferences.dart';

const settingsHapticsEnabledKey = 'settings_haptics_enabled';

/// Patrones disponibles usando solo `HapticFeedback` de Flutter (sin
/// CoreHaptics / VibrationEffect nativos).
enum PortyHapticPattern { selection, light, medium, heavy, doubleLight }

/// Vibración que acompaña cada palabra del texto de Porty mientras se tipea.
/// `lightImpact`: un escalón más de cuerpo que el tick de la burbuja del
/// usuario, así se nota que habla Porty.
const streamTickPattern = PortyHapticPattern.light;

/// Cada palabra del mensaje del usuario mientras se escribe en su burbuja
/// (después de enviar): el tick más seco y leve, textura y no golpes.
const userTypeTickPattern = PortyHapticPattern.selection;

/// Cooldown mínimo entre ticks de tipeo (Porty o usuario) — el typewriter
/// completa una
/// palabra cada ~100-150ms a 40 chars/s, pero palabras cortas ("a", "el")
/// pueden caer más juntas; esto evita saturar.
const streamTickCooldown = Duration(milliseconds: 100);

/// Cooldown del tick de scrub sobre un gráfico: en rangos largos hay más de
/// un punto por pixel y un drag rápido cruzaría decenas por frame.
const scrubTickCooldown = Duration(milliseconds: 35);

/// Toque que acompaña la entrada de cada widget de una respuesta, en el
/// mismo frame en que empieza a moverse (se abre su espacio y sube):
/// `mediumImpact`, claramente "llegó algo".
const widgetEntryPattern = PortyHapticPattern.medium;

/// El widget terminó de asentarse en su lugar: un tick seco y leve, como
/// el "clic" de algo que encaja. Golpe al arrancar + clic al llegar: la
/// vibración sigue el movimiento de la entrada.
const widgetSettlePattern = PortyHapticPattern.selection;

/// Cierre al terminar de entrar el último widget (en lugar de su clic de
/// asentamiento): `heavyImpact`, un escalón más firme que las entradas,
/// como un punto final.
const answerCompletePattern = PortyHapticPattern.heavy;

/// Respuesta de solo texto: un toque al terminar de tipear, un escalón más
/// que cada palabra.
const textAnswerPattern = PortyHapticPattern.medium;

/// Tocar algo bloqueado por plan: el "tick" seco de selección, en el mismo
/// frame del toque — confirma que se registró aunque la hoja tarde.
const lockedTapPattern = PortyHapticPattern.selection;

/// La hoja de paywall terminó de abrirse: un toque leve, el mismo cuerpo que
/// la entrada de un widget (algo "llegó"), nunca más fuerte.
const paywallOpenedPattern = PortyHapticPattern.light;

/// Las secciones de Gold se desbloquearon en el lugar tras comprar: el
/// mismo cierre que una respuesta completa ("listo").
const goldUnlockedPattern = PortyHapticPattern.medium;

/// Entraste (login, registro con sesión o vuelta de OAuth): un toque leve,
/// el mismo "llegó algo" de siempre, nunca un golpe de celebración.
const authSucceededPattern = PortyHapticPattern.light;

/// Algo del login falló (validación o servidor): dos toques leves seguidos,
/// el "no" más suave que permite `HapticFeedback` sin ir a lo nativo.
const authFailedPattern = PortyHapticPattern.doubleLight;

/// eToro quedó conectada o terminó de sincronizar a pedido del usuario: el
/// mismo "llegó algo" leve que entrar a la app, nunca un festejo.
const brokerSyncedPattern = PortyHapticPattern.light;

/// No se pudo conectar o sincronizar eToro: el "no" suave del login.
const brokerFailedPattern = PortyHapticPattern.doubleLight;

/// Único punto que dispara haptics de Porty: chequea el setting del usuario
/// antes de cada llamada, así ningún widget tiene que conocer el flag. Si el
/// usuario apagó las vibraciones a nivel sistema, `HapticFeedback` ya es un
/// no-op por su cuenta.
///
/// Todas las llamadas son fire-and-forget (no se awaitean): el canal de
/// plataforma es asíncrono y no debe frenar el frame que las dispara.
class PortyHapticsService {
  PortyHapticsService({
    required this.enabled,
    DateTime Function()? clock,
    Future<void> Function(PortyHapticPattern)? performer,
  }) : _clock = clock ?? DateTime.now,
       _performer = performer ?? _perform;

  bool enabled;
  final DateTime Function() _clock;
  final Future<void> Function(PortyHapticPattern) _performer;
  DateTime? _lastStreamTick;
  DateTime? _lastUserTypeTick;
  DateTime? _lastScrubTick;

  /// Busca el servicio en el `ProviderScope` ancestro sin crashear si no
  /// hay uno (widgets testeados en aislamiento) — devuelve `null` y el
  /// caller simplemente no vibra.
  static PortyHapticsService? maybeOf(BuildContext context) =>
      readProviderOrNull(context, portyHapticsServiceProvider);

  /// Una palabra nueva apareció en el stream del texto de Porty.
  void streamTick() {
    if (!enabled) return;
    final now = _clock();
    final last = _lastStreamTick;
    if (last != null && now.difference(last) < streamTickCooldown) return;
    _lastStreamTick = now;
    _performer(streamTickPattern);
  }

  /// Una palabra nueva apareció en la burbuja del mensaje del usuario.
  void userTypeTick() {
    if (!enabled) return;
    final now = _clock();
    final last = _lastUserTypeTick;
    if (last != null && now.difference(last) < streamTickCooldown) return;
    _lastUserTypeTick = now;
    _performer(userTypeTickPattern);
  }

  /// El dedo cruzó de un punto al siguiente scrubeando un gráfico.
  void scrubTick() {
    if (!enabled) return;
    final now = _clock();
    final last = _lastScrubTick;
    if (last != null && now.difference(last) < scrubTickCooldown) return;
    _lastScrubTick = now;
    _performer(PortyHapticPattern.selection);
  }

  /// Un widget de una respuesta arrancó su entrada. Vibran todos: las
  /// entradas van escalonadas (ver `RevealTiming.stagger`), así que nunca
  /// caen encima.
  void widgetEntryStarted() {
    if (!enabled) return;
    _performer(widgetEntryPattern);
  }

  /// Un widget (que no es el último) terminó de asentarse en su lugar.
  void widgetEntrySettled() {
    if (!enabled) return;
    _performer(widgetSettlePattern);
  }

  /// El último widget de la respuesta terminó de entrar.
  void answerRevealCompleted() {
    if (!enabled) return;
    _performer(answerCompletePattern);
  }

  /// Una respuesta de solo texto terminó de tipearse.
  void textAnswerRevealed() {
    if (!enabled) return;
    _performer(textAnswerPattern);
  }

  /// Se eligió una opción de un selector (ej. Activos / Insights) o se tocó
  /// una fila que navega: el tick seco de selección, en el mismo frame.
  void selectionTap() {
    if (!enabled) return;
    _performer(PortyHapticPattern.selection);
  }

  /// Se tocó un bloque o chip bloqueado por plan.
  void lockedTap() {
    if (!enabled) return;
    _performer(lockedTapPattern);
  }

  /// Se abrió la hoja de paywall.
  void paywallOpened() {
    if (!enabled) return;
    _performer(paywallOpenedPattern);
  }

  /// Las secciones de Gold de una card se desbloquearon tras comprar.
  void goldUnlocked() {
    if (!enabled) return;
    _performer(goldUnlockedPattern);
  }

  /// El usuario entró a la app desde el login.
  void authSucceeded() {
    if (!enabled) return;
    _performer(authSucceededPattern);
  }

  /// El login o el registro mostró un error (de un campo o del servidor).
  void authFailed() {
    if (!enabled) return;
    _performer(authFailedPattern);
  }

  /// eToro se conectó, o terminó una sincronización pedida por el usuario.
  void brokerSynced() {
    if (!enabled) return;
    _performer(brokerSyncedPattern);
  }

  /// Falló conectar o sincronizar eToro.
  void brokerFailed() {
    if (!enabled) return;
    _performer(brokerFailedPattern);
  }

  static Future<void> _perform(PortyHapticPattern pattern) async {
    switch (pattern) {
      case PortyHapticPattern.selection:
        await HapticFeedback.selectionClick();
      case PortyHapticPattern.light:
        await HapticFeedback.lightImpact();
      case PortyHapticPattern.medium:
        await HapticFeedback.mediumImpact();
      case PortyHapticPattern.heavy:
        await HapticFeedback.heavyImpact();
      case PortyHapticPattern.doubleLight:
        await HapticFeedback.lightImpact();
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await HapticFeedback.lightImpact();
    }
  }
}

class HapticsEnabledNotifier extends StateNotifier<bool> {
  HapticsEnabledNotifier(this._prefs)
    : super(_prefs.getBool(settingsHapticsEnabledKey) ?? true);

  final SharedPreferences _prefs;

  Future<void> setEnabled(bool value) async {
    await _prefs.setBool(settingsHapticsEnabledKey, value);
    state = value;
  }
}

/// Setting "Vibraciones al responder" — global (no autoDispose) porque lo
/// lee el chat aunque la pantalla de configuración no esté montada, mismo
/// patrón que `themeModeProvider`.
final hapticsEnabledProvider =
    StateNotifierProvider<HapticsEnabledNotifier, bool>((ref) {
      return HapticsEnabledNotifier(ref.watch(sharedPreferencesProvider));
    });

/// Instancia estable (conserva el estado del throttle) que se entera de los
/// cambios del setting en vez de recrearse.
final portyHapticsServiceProvider = Provider<PortyHapticsService>((ref) {
  final service = PortyHapticsService(
    enabled: ref.read(hapticsEnabledProvider),
  );
  ref.listen<bool>(hapticsEnabledProvider, (_, next) => service.enabled = next);
  return service;
});

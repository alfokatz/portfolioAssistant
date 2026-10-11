import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Por qué no se pudo dictar.
enum DictationFailure {
  /// El usuario no dio permiso de micrófono / reconocimiento de voz.
  permission,

  /// El dispositivo no tiene reconocimiento de voz (o falló al iniciarlo).
  unavailable,
}

/// Dictado del chat de Porty: el reconocimiento de voz del sistema
/// (`speech_to_text`), en el idioma de la app, con resultados parciales que
/// se van escribiendo en el campo. El texto nunca se envía solo: el
/// usuario lo revisa y toca enviar.
class ChatDictation extends ChangeNotifier {
  ChatDictation({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialized = false;
  bool _available = false;
  bool _listening = false;
  String? _localeId;

  bool get isListening => _listening;

  /// Empieza a escuchar. [onText] recibe la transcripción acumulada de esta
  /// sesión (parcial y final). Devuelve el motivo si no pudo empezar.
  Future<DictationFailure?> start({
    required String languageCode,
    required ValueChanged<String> onText,
  }) async {
    if (_listening) return null;
    if (!_initialized) {
      try {
        _available = await _speech.initialize(
          onStatus: _onStatus,
          onError: _onError,
        );
      } catch (e) {
        debugPrint('[Dictation] initialize: $e');
        _available = false;
      }
      _initialized = true;
    }
    if (!_available) {
      // initialize() pide los permisos: sin ellos devuelve false. Se vuelve
      // a intentar la próxima vez (el usuario puede darlos en Ajustes).
      _initialized = false;
      final hasPermission = await _speech.hasPermission;
      return hasPermission
          ? DictationFailure.unavailable
          : DictationFailure.permission;
    }
    _localeId ??= await _localeFor(languageCode);
    _listening = true;
    notifyListeners();
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) =>
            onText(result.recognizedWords),
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
          autoPunctuation: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('[Dictation] listen: $e');
      _setListening(false);
      return DictationFailure.unavailable;
    }
    return null;
  }

  Future<void> stop() async {
    if (!_listening) return;
    await _speech.stop();
    _setListening(false);
  }

  /// El locale del sistema que coincide con el idioma de la app (es-AR,
  /// es-ES… o el primero "es"); `null` = el del sistema.
  Future<String?> _localeFor(String languageCode) async {
    try {
      final locales = await _speech.locales();
      final system = await _speech.systemLocale();
      if (system != null && system.localeId.startsWith(languageCode)) {
        return system.localeId;
      }
      return locales
          .where((l) => l.localeId.toLowerCase().startsWith(languageCode))
          .firstOrNull
          ?.localeId;
    } catch (_) {
      return null;
    }
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _setListening(false);
    }
  }

  void _onError(SpeechRecognitionError error) {
    debugPrint('[Dictation] error: ${error.errorMsg}');
    _setListening(false);
  }

  void _setListening(bool value) {
    if (_listening == value) return;
    _listening = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_listening) _speech.cancel();
    super.dispose();
  }
}

/// Una por pantalla de chat (la pestaña queda montada en el shell).
final chatDictationProvider = ChangeNotifierProvider.autoDispose<ChatDictation>(
  (ref) => ChatDictation(),
);

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';

/// El estado del avatar del mensaje en curso (el que está al lado de la
/// respuesta, ver `AssistantScreen`) a lo largo de un turno:
///
/// idle → thinking (corre el turno: modelo y tools) → answering (typewriter
/// de la respuesta) → answered (3 s) → idle. Si la respuesta muestra una
/// mala noticia, de answering va directo a idle. Error, sin datos o tope de
/// consultas → error, hasta el próximo turno.
///
/// Lo maneja la pantalla del chat: [working] sigue a `TurnActivity`, y el
/// resto lo decide al cerrar el turno y cuando termina el typewriter (ver
/// [PortyVoiceScope]).
class PortyMood extends ValueNotifier<PortyAvatarState> {
  PortyMood({this.answeredHold = const Duration(seconds: 3)})
    : super(PortyAvatarState.idle);

  /// Cuánto dura la sonrisa antes de volver a idle.
  final Duration answeredHold;

  Timer? _rest;

  void working() => _set(PortyAvatarState.thinking);

  /// Arranca el typewriter de la respuesta.
  void speaking() => _set(PortyAvatarState.answering);

  /// Terminó el texto de la respuesta. Solo cuenta si estaba hablando (una
  /// surface vieja que se reconstruye no cambia nada).
  void doneSpeaking({required bool goodNews}) {
    if (value != PortyAvatarState.answering) return;
    if (!goodNews) {
      _set(PortyAvatarState.idle);
      return;
    }
    _set(PortyAvatarState.answered);
    _rest = Timer(answeredHold, () => _set(PortyAvatarState.idle));
  }

  void failed() => _set(PortyAvatarState.error);

  void rest() => _set(PortyAvatarState.idle);

  void _set(PortyAvatarState state) {
    _rest?.cancel();
    _rest = null;
    value = state;
  }

  @override
  void dispose() {
    _rest?.cancel();
    super.dispose();
  }
}

/// Le avisa a la pantalla cuándo termina de tipearse el texto de la
/// respuesta en curso. Va alrededor de toda surface (siempre, para no
/// cambiar la forma del árbol y remontarla), pero solo la del turno actual
/// lleva [onDoneSpeaking]: las respuestas viejas, que se remontan al
/// scrollear, no mueven al avatar. Se lee recién al terminar el texto, así
/// que toma el callback vigente en ese momento.
class PortyVoiceScope extends InheritedWidget {
  const PortyVoiceScope({
    super.key,
    required this.onDoneSpeaking,
    required super.child,
  });

  final VoidCallback? onDoneSpeaking;

  static PortyVoiceScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PortyVoiceScope>();

  @override
  bool updateShouldNotify(PortyVoiceScope oldWidget) => false;
}

import 'dart:math' as math;
import 'dart:ui' show PathMetric, lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_accessory_painter.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_breath.dart';
import 'package:portfolio_assistant/features/porty_outfit/domain/porty_outfit.dart';

/// Qué está haciendo Porty. Cada estado es una expresión de la misma cara
/// (ver `assets/porty-avatar/states/`) y, si el avatar es animado, un
/// movimiento del cuerpo (ver [PortyAvatarMotion]).
enum PortyAvatarState {
  /// Sin turno en curso: sonrisa leve; respira, parpadea y cada tanto mira
  /// a un costado.
  idle,

  /// Corren las tools: ojos arriba y boca chica hacia un costado; se inclina
  /// y flota, el destello titila.
  thinking,

  /// Corre el typewriter de la respuesta: la boca habla, el cuerpo respira.
  answering,

  /// Terminó una respuesta sin malas noticias: saltito y sonrisa.
  answered,

  /// Terminó una respuesta con una mala noticia sobre la cartera: apenas
  /// triste (boca en arco suave hacia abajo y un suspiro corto). Más leve
  /// que [error].
  concerned,

  /// Error, sin datos o tope de consultas: un "no" corto y queda quieto.
  error,
}

/// Las partes de la cara, con los mismos ids que los SVG.
enum PortyPart { body, eyes, mouth, spark }

/// Cómo piensa Porty ([PortyAvatarState.thinking]).
enum PortyThinkingStyle {
  /// Se inclina y flota, con el destello (header, informe, loaders).
  standard,

  /// El de un mensaje del chat, en el lugar donde va a empezar la
  /// respuesta, y el del arranque de la app: el pulso de escala y opacidad del orbe que había antes
  /// (mismo ciclo y curva), su deriva vertical y su halo, un eco del
  /// contorno que se expande, ojos arriba y sin destello.
  pulse,
}

/// Colores de Porty. [brand] va igual en light y en dark: el terracota tiene
/// ~7:1 contra el fondo dark (#0F0F0F) y los ojos ~4,9:1 contra el cuerpo.
@immutable
class PortyAvatarPalette {
  const PortyAvatarPalette({
    required this.body,
    required this.features,
    Color? spark,
  }) : spark = spark ?? body;

  final Color body;

  /// Ojos y boca.
  final Color features;

  /// Destello de [PortyAvatarState.thinking].
  final Color spark;

  static const brand = PortyAvatarPalette(
    body: Color(0xFFD98E5D),
    features: Color(0xFF2F3437),
  );

  /// `porty_*_mono_dark.svg`: una sola tinta oscura, para fondos claros.
  static const monoDark = PortyAvatarPalette(
    body: Color(0xFF2F3437),
    features: Color(0xFFFBFBFA),
  );

  /// `porty_*_mono_light.svg`: una sola tinta clara, para fondos oscuros.
  static const monoLight = PortyAvatarPalette(
    body: Color(0xFFFBFBFA),
    features: Color(0xFF191A1B),
  );

  @override
  bool operator ==(Object other) =>
      other is PortyAvatarPalette &&
      other.body == body &&
      other.features == features &&
      other.spark == spark;

  @override
  int get hashCode => Object.hash(body, features, spark);
}

/// Todos los tiempos, amplitudes y curvas de Porty, para ajustarlos a ojo.
///
/// Las distancias están en unidades del dibujo: la caja del avatar mide
/// [PortyAvatarPainter.boxUnits] (72) y el cuerpo 50. En el header (caja de
/// 50 px) 1 u ≈ 0,69 px; en el login (80 px) 1 u ≈ 1,1 px.
abstract final class PortyAvatarMotion {
  /// Crossfade de ojos, boca y destello al cambiar de estado.
  static const crossfade = Duration(milliseconds: 180);
  static const crossfadeCurve = Curves.easeOutCubic;

  /// Encadenado del cuerpo entre estados: desde la pose en la que estaba
  /// (a mitad de una respiración o de la inclinación) hasta la del estado
  /// nuevo, sin saltos.
  static const poseBlend = Duration(milliseconds: 400);
  static const poseBlendCurve = Curves.easeInOutCubic;

  // idle / answering / answered: respiración.
  static const breathPeriod = Duration(milliseconds: 3500);
  static const breathScale = 1.015;

  // idle: parpadeo y mirada.
  static const blink = Duration(milliseconds: 120);
  static const blinkGapMin = Duration(seconds: 4);
  static const blinkGapMax = Duration(seconds: 6);
  static const glance = Duration(milliseconds: 400);
  static const glanceGapMin = Duration(seconds: 8);
  static const glanceGapMax = Duration(seconds: 12);

  /// Cuánto se corren los ojos al mirar a un costado o hacia un toque.
  static const lookDistance = 2.2;

  // thinking.
  static const thinkPeriod = Duration(milliseconds: 1600);

  /// Inclinación hacia el destello (sentido horario), en grados.
  static const thinkLeanDegrees = 4.0;

  /// Flotación hacia arriba (≈1,5 px en el header).
  static const thinkFloat = 2.2;
  static const sparkPeriod = Duration(milliseconds: 800);

  // answering.
  static const talkPeriod = Duration(milliseconds: 450);

  // answered.
  static const smile = Duration(milliseconds: 300);

  /// Saltito: sube y baja una vez, sin rebote (≈3 px en el header).
  static const hop = Duration(milliseconds: 350);
  static const hopHeight = 4.3;
  static const hopCurve = Curves.easeOutCubic;

  // concerned: la boca se traza como la sonrisa ([smile]) y el cuerpo baja
  // apenas y vuelve, como un suspiro.
  static const sigh = Duration(milliseconds: 700);
  static const sighDepth = 1.5;

  // error: "no" con la cabeza.
  static const shake = Duration(milliseconds: 400);
  static const shakeDegrees = 3.0;
  static const shakeCycles = 2;

  // Toque en el avatar del header: mira hacia el toque y salta.
  static const tapLook = Duration(milliseconds: 600);
  static const tapHopHeight = 3.0;

  // thinking del chat ([PortyThinkingStyle.pulse]): el ritmo del orbe.
  /// Ciclo del pulso: el del orbe (`PortyBreath.period`).
  static const pulsePeriod = PortyBreath.period;
  static const pulseScaleMin = 0.86;
  static const pulseScaleMax = 1.08;
  static const pulseOpacityMin = 0.8;

  /// Deriva vertical del orbe: ciclo distinto del pulso (no múltiplo), así
  /// la combinación no se repite igual. ≈ 1,75 px a 36 px.
  static const pulseDriftPeriod = Duration(milliseconds: 2600);
  static const pulseDrift = 3.5;

  /// Halo del orbe: dos capas difusas de terracota detrás del cuerpo, que
  /// respiran con el pulso (opacidad 0,55 → 0,9 × su alfa). Blur en
  /// unidades (cuerpo = 50), con las proporciones de las sombras del orbe.
  static const haloOpacityMin = 0.55;
  static const haloOpacityMax = 0.9;
  static const haloInnerAlpha = 0.45;
  static const haloInnerBlur = 0.6 * 50;
  static const haloOuterAlpha = 0.35;
  static const haloOuterBlur = 0.95 * 50;

  /// Eco: contorno del cuerpo que crece y se desvanece en cada ciclo.
  static const echoScaleTo = 1.35;
  static const echoOpacity = 0.3;
  static const echoStrokeWidth = 2.0;

  /// Al dejar de pensar, el pulso desacelera hasta escala 1 y el eco se
  /// apaga; recién después cambia la expresión.
  static const pulseSettle = Duration(milliseconds: 320);
  static const pulseSettleCurve = Curves.easeOutCubic;

  // Entrada (login, primera vez del chat en la sesión).
  static const entrance = Duration(milliseconds: 300);
  static const entranceScaleFrom = 0.9;
  static const entranceCurve = Curves.easeOutCubic;
}

/// Lo que se pinta en un frame. Es público para que los tests comparen las
/// partes visibles y la pose sin goldens.
@immutable
class PortyFrame {
  const PortyFrame({
    required this.state,
    this.from,
    this.crossfade = 1,
    this.dy = 0,
    this.rotation = 0,
    this.scale = 1,
    this.opacity = 1,
    this.eyeOffset = Offset.zero,
    this.blink = 0,
    this.mouthScale = 1,
    this.smile = 1,
    this.sparkGlow = 1,
    this.spark = true,
    this.bodyOpacity = 1,
    this.echoScale = 1,
    this.echoOpacity = 0,
    this.haloOpacity = 0,
  });

  /// Cómo se ve [state] en reposo (sin animación). [spark] en `false` para
  /// [PortyThinkingStyle.pulse].
  const PortyFrame.still(this.state, {this.spark = true})
    : from = null,
      crossfade = 1,
      dy = 0,
      rotation = 0,
      scale = 1,
      opacity = 1,
      eyeOffset = Offset.zero,
      blink = 0,
      mouthScale = 1,
      smile = 1,
      sparkGlow = 1,
      bodyOpacity = 1,
      echoScale = 1,
      echoOpacity = 0,
      haloOpacity = 0;

  final PortyAvatarState state;

  /// Estado que se está yendo mientras dura el crossfade de la cara.
  final PortyAvatarState? from;

  /// 0 → 1 (ya con curva): opacidad de la cara de [state]; [from] la inversa.
  final double crossfade;

  /// Pose del cuerpo alrededor de su centro: desplazamiento vertical (en
  /// unidades, negativo = arriba), rotación (radianes) y escala.
  final double dy;
  final double rotation;
  final double scale;

  /// Opacidad del avatar entero (entrada).
  final double opacity;

  /// Hacia dónde miran los ojos, en unidades.
  final Offset eyeOffset;

  /// 0 = ojos abiertos, 1 = cerrados.
  final double blink;

  /// Alto de la boca de [PortyAvatarState.answering] relativo al SVG.
  final double mouthScale;

  /// 0 → 1: cuánto de la boca de [PortyAvatarState.answered] (sonrisa) o
  /// [PortyAvatarState.concerned] (arco hacia abajo) está trazado.
  final double smile;

  /// 0 → 1: opacidad del destello.
  final double sparkGlow;

  /// Si thinking lleva destello ([PortyThinkingStyle.standard]).
  final bool spark;

  /// Opacidad del cuerpo (pulso de [PortyThinkingStyle.pulse]).
  final double bodyOpacity;

  /// Eco del contorno detrás del cuerpo ([PortyThinkingStyle.pulse]).
  final double echoScale;
  final double echoOpacity;

  /// Halo difuso detrás del cuerpo ([PortyThinkingStyle.pulse]).
  final double haloOpacity;

  /// `true` si el cuerpo está en su pose de reposo.
  bool get bodyAtRest =>
      dy == 0 && rotation == 0 && scale == 1 && bodyOpacity == 1;

  static Set<PortyPart> partsOf(PortyAvatarState state) => {
    PortyPart.body,
    PortyPart.eyes,
    PortyPart.mouth,
    if (state == PortyAvatarState.thinking) PortyPart.spark,
  };

  /// Partes con algo de opacidad en este frame.
  Set<PortyPart> get visibleParts {
    const minAlpha = 0.01;
    final parts = <PortyPart>{PortyPart.body, PortyPart.eyes};
    void add(PortyAvatarState s, double alpha) {
      if (alpha <= minAlpha) return;
      for (final part in partsOf(s)) {
        if (part == PortyPart.spark &&
            (!spark || alpha * sparkGlow <= minAlpha)) {
          continue;
        }
        // La boca que se va ya estaba trazada entera (ver PortyAvatarPainter).
        if (part == PortyPart.mouth &&
            s == state &&
            (s == PortyAvatarState.answered ||
                s == PortyAvatarState.concerned) &&
            smile <= 0) {
          continue;
        }
        parts.add(part);
      }
    }

    add(state, from == null ? 1 : crossfade);
    if (from != null) add(from!, 1 - crossfade);
    return parts;
  }

  @override
  bool operator ==(Object other) =>
      other is PortyFrame &&
      other.state == state &&
      other.from == from &&
      other.crossfade == crossfade &&
      other.dy == dy &&
      other.rotation == rotation &&
      other.scale == scale &&
      other.opacity == opacity &&
      other.eyeOffset == eyeOffset &&
      other.blink == blink &&
      other.mouthScale == mouthScale &&
      other.smile == smile &&
      other.sparkGlow == sparkGlow &&
      other.spark == spark &&
      other.bodyOpacity == bodyOpacity &&
      other.echoScale == echoScale &&
      other.echoOpacity == echoOpacity &&
      other.haloOpacity == haloOpacity;

  @override
  int get hashCode => Object.hash(
    state,
    from,
    crossfade,
    dy,
    rotation,
    scale,
    opacity,
    eyeOffset,
    blink,
    mouthScale,
    smile,
    sparkGlow,
    spark,
    bodyOpacity,
    echoScale,
    echoOpacity,
    haloOpacity,
  );
}

/// La cara de Porty: el "guijarro" terracota con ojos, que cambia de
/// expresión según [state]. Es el único avatar de Porty de la app (header
/// del chat, login, informe semanal, onboarding, paywall, nav bar).
///
/// [size] es el lado de la caja (lo que ocupa en el layout). El cuerpo mide
/// ~70 % de la caja, centrado; el resto es margen para el destello, el
/// saltito y la inclinación, así ninguna animación cambia el layout.
///
/// Con [animated] en `false` (default) es un dibujo estático del estado.
/// Con `true` se anima con un único [Ticker] (ver [PortyAvatarMotion]): la
/// cara hace crossfade al cambiar de estado y el cuerpo encadena su
/// movimiento desde la pose en la que estaba. El ticker se detiene con el
/// `TickerMode` apagado (pestaña oculta), con la app en background y
/// cuando no hay nada que mover (error ya quieto). Con reduce motion no hay
/// movimiento: solo cambia la expresión.
class PortyAvatar extends StatefulWidget {
  const PortyAvatar({
    super.key,
    this.state = PortyAvatarState.idle,
    this.size = defaultSize,
    this.animated = false,
    this.entrance = false,
    this.palette = PortyAvatarPalette.brand,
    this.onTap,
    this.thinkingStyle = PortyThinkingStyle.standard,
    this.outfit,
  });

  final PortyAvatarState state;

  /// Accesorios puestos. `null` = los del usuario ([PortyOutfitScope]); solo
  /// se dibujan con la paleta de marca.
  final PortyOutfit? outfit;

  /// Cómo se ve [PortyAvatarState.thinking] (ver [PortyThinkingStyle]).
  final PortyThinkingStyle thinkingStyle;
  final double size;
  final bool animated;

  /// Aparece con fade + escala 0,9 → 1 y un parpadeo (solo si [animated]).
  final bool entrance;
  final PortyAvatarPalette palette;

  /// Si no es `null`, tocar el avatar lo hace mirar hacia el toque y dar un
  /// saltito (si [animated]); después se llama esto (p. ej. un haptic).
  final VoidCallback? onTap;

  /// Header del chat.
  static const defaultSize = 50.0;

  /// Respiración, parpadeo y mirada en reposo: lo único que se mueve sin
  /// que pase nada. Los tests que necesitan `pumpAndSettle` con un avatar
  /// animado en pantalla lo apagan.
  @visibleForTesting
  static bool ambientMotion = true;

  @override
  State<PortyAvatar> createState() => _PortyAvatarState();
}

class _PortyAvatarState extends State<PortyAvatar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static final _random = math.Random();
  static const _never = -1e9;

  late final Ticker _ticker = createTicker(_onTick);

  /// Reloj del avatar en segundos. Solo avanza mientras el ticker corre:
  /// al pausar (background, pestaña oculta) queda congelado y al volver
  /// sigue desde ahí, sin saltos.
  double _now = 0;
  double _clockBase = 0;

  /// El estado que se ve. Casi siempre es `widget.state`; al salir del
  /// pulso del chat, sigue en thinking mientras el pulso se asienta
  /// ([_pending] es el que viene).
  late PortyAvatarState _shown = widget.state;
  PortyAvatarState? _pending;
  double _settleAt = _never;
  _Pose _settleFrom = _Pose.rest;

  // Cara.
  PortyAvatarState? _from;
  double _stateAt = _never;
  double _thinkingAt = _never;

  // Cuerpo: pose de la que se parte al cambiar de estado.
  _Pose _poseFrom = _Pose.rest;
  double _poseAt = _never;

  // Movimientos de una vez (se suman a la pose del estado).
  double _hopAt = _never;
  double _hopHeight = 0;
  double _shakeAt = _never;
  double _sighAt = _never;
  double _entranceAt = _never;
  bool _entrancePending = false;

  // Ojos.
  double _blinkAt = _never;
  double _nextBlinkAt = double.infinity;
  double _glanceAt = _never;
  double _nextGlanceAt = double.infinity;
  double _glanceSide = 1;
  double _lookAt = _never;
  Offset _lookDirection = Offset.zero;

  bool _appActive = true;
  bool _tickerModeOn = true;
  bool _reduceMotion = false;

  late PortyFrame _frame = _still(widget.state);

  bool get _pulse => widget.thinkingStyle == PortyThinkingStyle.pulse;

  PortyFrame _still(PortyAvatarState state) =>
      PortyFrame.still(state, spark: !_pulse);

  bool get _canMove => widget.animated && !_reduceMotion;
  bool get _visible => _appActive && _tickerModeOn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _entrancePending = widget.animated && widget.entrance;
    _enterState(widget.state, initial: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _tickerModeOn = TickerMode.valuesOf(context).enabled;
    _sync(rebuild: false);
  }

  @override
  void didUpdateWidget(PortyAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      final target = widget.state;
      if (_pending != null) {
        if (target == PortyAvatarState.thinking) {
          // Vuelve a pensar antes de asentarse: retoma el pulso desde acá.
          _poseFrom = _basePose(PortyAvatarState.thinking, _now);
          _poseAt = _now;
          _pending = null;
        } else {
          _pending = target;
        }
      } else if (_pulse &&
          _canMove &&
          _shown == PortyAvatarState.thinking &&
          target != PortyAvatarState.thinking) {
        // El pulso termina desacelerando hasta escala 1 y el eco se apaga;
        // recién ahí cambia la expresión (ver _onTick).
        _settleFrom = _basePose(PortyAvatarState.thinking, _now);
        _settleAt = _now;
        _pending = target;
      } else {
        _transitionTo(target);
      }
    }
    _sync(rebuild: false);
  }

  void _transitionTo(PortyAvatarState target, {_Pose? from}) {
    // La pose de la que se parte es la de este instante (a mitad de lo que
    // estuviera haciendo), no la de reposo.
    _poseFrom = from ?? _basePose(_shown, _now);
    _poseAt = _now;
    _from = _shown;
    _shown = target;
    _enterState(target);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active == _appActive) return;
    _appActive = active;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  void _enterState(PortyAvatarState state, {bool initial = false}) {
    _stateAt = initial ? _never : _now;
    if (initial) _from = null;
    switch (state) {
      case PortyAvatarState.idle:
        _nextBlinkAt =
            _now +
            _randomGap(
              PortyAvatarMotion.blinkGapMin,
              PortyAvatarMotion.blinkGapMax,
            );
        _nextGlanceAt =
            _now +
            _randomGap(
              PortyAvatarMotion.glanceGapMin,
              PortyAvatarMotion.glanceGapMax,
            );
      case PortyAvatarState.answered:
        if (!initial) _startHop(PortyAvatarMotion.hopHeight);
      case PortyAvatarState.concerned:
        if (!initial) _sighAt = _now;
      case PortyAvatarState.error:
        if (!initial) _shakeAt = _now;
      case PortyAvatarState.thinking:
        // El ciclo (pulso, destello) arranca cuando empieza a pensar, también
        // si se monta ya pensando.
        _thinkingAt = initial ? _now : _stateAt;
      case PortyAvatarState.answering:
        break;
    }
  }

  static double _seconds(Duration d) => d.inMicroseconds / 1e6;

  /// Progreso lineal de un movimiento que arrancó en [start]. Termina en 1
  /// exacto (sin residuo de punto flotante), así la pose final es la de
  /// reposo y [_settled] coincide con lo que se pinta.
  static double _progress(double t, double start, Duration d) {
    final p = (t - start) / _seconds(d);
    return p > 1 - 1e-9 ? 1 : p;
  }

  static double _randomGap(Duration min, Duration max) =>
      _seconds(min) + _random.nextDouble() * _seconds(max - min);

  void _startHop(double height) {
    // Un saltito no corta a otro a mitad de camino.
    if (_now - _hopAt < _seconds(PortyAvatarMotion.hop)) return;
    _hopAt = _now;
    _hopHeight = height;
  }

  /// Arranca o detiene el ticker según lo que haya que mover. Desde
  /// `didUpdateWidget`/`didChangeDependencies` ([rebuild] en `false`) solo
  /// actualiza el frame: el build viene igual.
  void _sync({bool rebuild = true}) {
    if (!_canMove) {
      _stopTicker();
      _from = null;
      _pending = null;
      _shown = widget.state;
      _setFrame(_still(widget.state), rebuild: rebuild);
      return;
    }
    if (_entrancePending && _visible) {
      _entrancePending = false;
      _entranceAt = _now;
      // Parpadeo al terminar de entrar.
      _nextBlinkAt = _now + _seconds(PortyAvatarMotion.entrance);
    }
    if (_visible && !_settled) {
      if (!_ticker.isActive) {
        _clockBase = _now;
        _ticker.start();
      }
    } else {
      _stopTicker();
    }
    _setFrame(_compose(), rebuild: rebuild);
  }

  void _stopTicker() {
    if (!_ticker.isActive) return;
    _ticker.stop();
    _clockBase = _now;
  }

  /// Nada más que mover: la cara terminó su crossfade, el cuerpo llegó a su
  /// pose y no queda ningún movimiento de una vez en curso, en un estado
  /// sin loop (error, o cualquiera sin [PortyAvatar.ambientMotion]).
  bool get _settled {
    if (_pending != null) return false;
    final state = _shown;
    final looping = switch (state) {
      PortyAvatarState.thinking || PortyAvatarState.answering => true,
      PortyAvatarState.error => false,
      _ => PortyAvatar.ambientMotion,
    };
    if (looping) return false;
    bool done(double start, Duration d) => _progress(_now, start, d) >= 1;
    return done(_stateAt, PortyAvatarMotion.crossfade) &&
        done(_poseAt, PortyAvatarMotion.poseBlend) &&
        done(_hopAt, PortyAvatarMotion.hop) &&
        done(_shakeAt, PortyAvatarMotion.shake) &&
        done(_sighAt, PortyAvatarMotion.sigh) &&
        done(_entranceAt, PortyAvatarMotion.entrance) &&
        done(_lookAt, PortyAvatarMotion.tapLook) &&
        done(_blinkAt, PortyAvatarMotion.blink) &&
        (state != PortyAvatarState.answered &&
                state != PortyAvatarState.concerned ||
            done(_stateAt, PortyAvatarMotion.smile));
  }

  void _onTick(Duration elapsed) {
    _now = _clockBase + elapsed.inMicroseconds / 1e6;
    final pending = _pending;
    if (pending != null &&
        _progress(_now, _settleAt, PortyAvatarMotion.pulseSettle) >= 1) {
      // La pose de partida es la ya asentada (escala 1), no la del pulso.
      final settled = _basePose(_shown, _now);
      _pending = null;
      _transitionTo(pending, from: settled);
    }
    if (_shown == PortyAvatarState.idle && PortyAvatar.ambientMotion) {
      if (_now >= _nextBlinkAt) {
        _blinkAt = _now;
        _nextBlinkAt =
            _now +
            _randomGap(
              PortyAvatarMotion.blinkGapMin,
              PortyAvatarMotion.blinkGapMax,
            );
      }
      if (_now >= _nextGlanceAt) {
        _glanceAt = _now;
        _glanceSide = _random.nextBool() ? 1 : -1;
        _nextGlanceAt =
            _now +
            _randomGap(
              PortyAvatarMotion.glanceGapMin,
              PortyAvatarMotion.glanceGapMax,
            );
      }
    } else if (_shown == PortyAvatarState.idle && _now >= _nextBlinkAt) {
      // Sin movimiento ambiente igual parpadea al terminar la entrada.
      _blinkAt = _now;
      _nextBlinkAt = double.infinity;
    }
    if (_settled) _stopTicker();
    _setFrame(_compose());
  }

  void _setFrame(PortyFrame frame, {bool rebuild = true}) {
    if (frame == _frame || !mounted) return;
    if (rebuild) {
      setState(() => _frame = frame);
    } else {
      _frame = frame;
    }
  }

  void _handleTap(TapUpDetails details) {
    if (_canMove && _visible) {
      final box = widget.size;
      final fromCenter = details.localPosition - Offset(box / 2, box / 2);
      final distance = fromCenter.distance;
      _lookDirection =
          distance < box * 0.08 ? Offset.zero : fromCenter / distance;
      _lookAt = _now;
      _startHop(PortyAvatarMotion.tapHopHeight);
      _sync();
    }
    widget.onTap?.call();
  }

  // --- Composición del frame ---------------------------------------------

  /// 0 → 1 → 0 suave (coseno) con período [period].
  static double _wave(double t, Duration period) =>
      0.5 - 0.5 * math.cos(2 * math.pi * t / _seconds(period));

  /// Pose propia de [state] en el instante [t] (sin encadenado).
  _Pose _statePose(PortyAvatarState state, double t) {
    final breath =
        PortyAvatar.ambientMotion
            ? 1 +
                (PortyAvatarMotion.breathScale - 1) *
                    _wave(t, PortyAvatarMotion.breathPeriod)
            : 1.0;
    return switch (state) {
      PortyAvatarState.idle ||
      PortyAvatarState.answering ||
      PortyAvatarState.answered ||
      PortyAvatarState.concerned => _Pose(scale: breath),
      PortyAvatarState.thinking when _pulse => _pulsePose(t),
      PortyAvatarState.thinking => _Pose(
        rotation: PortyAvatarMotion.thinkLeanDegrees * math.pi / 180,
        dy:
            -PortyAvatarMotion.thinkFloat *
            _wave(t - _stateAt, PortyAvatarMotion.thinkPeriod),
      ),
      PortyAvatarState.error => _Pose.rest,
    };
  }

  /// Fase (0..1) del ciclo del pulso del chat.
  double _pulsePhase(double t) {
    final cycles = (t - _thinkingAt) / _seconds(PortyAvatarMotion.pulsePeriod);
    return cycles - cycles.floorToDouble();
  }

  /// El pulso del orbe aplicado al cuerpo: misma onda (`PortyBreath.wave`,
  /// ease in-out sinusoidal en cada mitad), rangos acotados al personaje.
  _Pose _pulsePose(double t) {
    final w = PortyBreath.wave(_pulsePhase(t));
    final drift =
        (t - _thinkingAt) / _seconds(PortyAvatarMotion.pulseDriftPeriod);
    return _Pose(
      dy: -PortyAvatarMotion.pulseDrift * math.sin(2 * math.pi * drift),
      scale:
          lerpDouble(
            PortyAvatarMotion.pulseScaleMin,
            PortyAvatarMotion.pulseScaleMax,
            w,
          )!,
      opacity: lerpDouble(PortyAvatarMotion.pulseOpacityMin, 1, w)!,
    );
  }

  /// 0..1 del asentamiento del pulso al dejar de pensar (con curva).
  double _settleProgress(double t) =>
      PortyAvatarMotion.pulseSettleCurve.transform(
        _progress(t, _settleAt, PortyAvatarMotion.pulseSettle).clamp(0.0, 1.0),
      );

  /// Eco del contorno: nace en cada ciclo, crece y se desvanece a 0. Al
  /// asentarse el pulso, se apaga con él.
  ({double scale, double opacity, double halo}) _echo(double t) {
    if (!_pulse || _shown != PortyAvatarState.thinking) {
      return (scale: 1, opacity: 0, halo: 0);
    }
    final p = _pulsePhase(t);
    // Mientras entra (desde otra pose) y mientras se asienta, atenuados.
    var presence = _progress(
      t,
      _poseAt,
      PortyAvatarMotion.poseBlend,
    ).clamp(0.0, 1.0);
    if (_pending != null) presence *= 1 - _settleProgress(t);
    return (
      scale:
          1 +
          (PortyAvatarMotion.echoScaleTo - 1) *
              Curves.easeOutCubic.transform(p),
      opacity:
          presence *
          PortyAvatarMotion.echoOpacity *
          (1 - p) *
          (p / 0.08).clamp(0.0, 1.0),
      // El halo respira con el cuerpo, como el del orbe.
      halo:
          presence *
          lerpDouble(
            PortyAvatarMotion.haloOpacityMin,
            PortyAvatarMotion.haloOpacityMax,
            PortyBreath.wave(p),
          )!,
    );
  }

  /// Pose de [state] encadenada desde [_poseFrom].
  _Pose _basePose(PortyAvatarState state, double t) {
    if (_pending != null && state == PortyAvatarState.thinking) {
      // Asentándose: desde donde estaba el pulso hasta el reposo, frenando.
      return _Pose.lerp(_settleFrom, _Pose.rest, _settleProgress(t));
    }
    final target = _statePose(state, t);
    final p = _progress(t, _poseAt, PortyAvatarMotion.poseBlend);
    if (p >= 1) return target;
    return _Pose.lerp(
      _poseFrom,
      target,
      PortyAvatarMotion.poseBlendCurve.transform(p.clamp(0.0, 1.0)),
    );
  }

  /// Suspiro de [PortyAvatarState.concerned]: baja apenas y vuelve, lento.
  double _sighOffset(double t) {
    final p = _progress(t, _sighAt, PortyAvatarMotion.sigh);
    if (p <= 0 || p >= 1) return 0;
    return PortyAvatarMotion.sighDepth *
        math.sin(math.pi * Curves.easeInOutSine.transform(p));
  }

  /// Sube rápido y baja suave, una vez: `sin(π·easeOutCubic(p))`.
  double _hopOffset(double t) {
    final p = _progress(t, _hopAt, PortyAvatarMotion.hop);
    if (p <= 0 || p >= 1) return 0;
    return -_hopHeight *
        math.sin(math.pi * PortyAvatarMotion.hopCurve.transform(p));
  }

  double _shakeRotation(double t) {
    final p = _progress(t, _shakeAt, PortyAvatarMotion.shake);
    if (p <= 0 || p >= 1) return 0;
    // Arranca y termina con velocidad cero: sin tirón al empezar ni rebote.
    final eased = Curves.easeInOutSine.transform(p);
    return PortyAvatarMotion.shakeDegrees *
        math.pi /
        180 *
        math.sin(2 * math.pi * PortyAvatarMotion.shakeCycles * eased);
  }

  /// Ida, pausa y vuelta: 0 → 1 (30 %), 1 (40 %), 1 → 0 (30 %).
  static double _outAndBack(double p) {
    if (p <= 0 || p >= 1) return 0;
    if (p < 0.3) return Curves.easeOutCubic.transform(p / 0.3);
    if (p > 0.7) return Curves.easeInOutCubic.transform((1 - p) / 0.3);
    return 1;
  }

  PortyFrame _compose() {
    final state = _shown;
    if (!_canMove) return _still(state);
    final t = _now;

    final face = _progress(
      t,
      _stateAt,
      PortyAvatarMotion.crossfade,
    ).clamp(0.0, 1.0);
    final from = face < 1 ? _from : null;

    final pose = _basePose(state, t);
    final entrance = _progress(
      t,
      _entranceAt,
      PortyAvatarMotion.entrance,
    ).clamp(0.0, 1.0);
    final entering = PortyAvatarMotion.entranceCurve.transform(entrance);
    final hasEntrance = _entranceAt != _never || _entrancePending;
    final entranceScale =
        hasEntrance
            ? lerpDouble(PortyAvatarMotion.entranceScaleFrom, 1, entering)!
            : 1.0;

    final blinkP = _progress(t, _blinkAt, PortyAvatarMotion.blink);
    final blink = blinkP > 0 && blinkP < 1 ? 1 - (2 * blinkP - 1).abs() : 0.0;

    final glance = _outAndBack(
      _progress(t, _glanceAt, PortyAvatarMotion.glance),
    );
    final look = _outAndBack(_progress(t, _lookAt, PortyAvatarMotion.tapLook));
    var eyeOffset = Offset(_glanceSide * glance, 0) + _lookDirection * look;
    if (eyeOffset.distance > 1) eyeOffset = eyeOffset / eyeOffset.distance;
    eyeOffset *= PortyAvatarMotion.lookDistance;

    final echo = _echo(t);

    final smile = Curves.easeOutCubic.transform(
      _progress(t, _stateAt, PortyAvatarMotion.smile).clamp(0.0, 1.0),
    );

    return PortyFrame(
      state: state,
      from: from,
      crossfade:
          from == null ? 1 : PortyAvatarMotion.crossfadeCurve.transform(face),
      dy: pose.dy + _hopOffset(t) + _sighOffset(t),
      rotation: pose.rotation + _shakeRotation(t),
      scale: pose.scale * entranceScale,
      opacity: hasEntrance ? entering : 1,
      bodyOpacity: pose.opacity,
      echoScale: echo.scale,
      echoOpacity: echo.opacity,
      haloOpacity: echo.halo,
      spark: !_pulse,
      eyeOffset: eyeOffset,
      blink: blink,
      mouthScale:
          state == PortyAvatarState.answering
              ? 0.45 + 0.85 * _wave(t - _stateAt, PortyAvatarMotion.talkPeriod)
              : 1,
      smile: smile,
      // El destello titila desde que empezó a pensar y sigue su fase
      // mientras se desvanece; fuera de thinking queda en 1 (reposo).
      sparkGlow:
          state == PortyAvatarState.thinking ||
                  from == PortyAvatarState.thinking
              ? 0.3 +
                  0.7 * _wave(t - _thinkingAt, PortyAvatarMotion.sparkPeriod)
              : 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget avatar = RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: PortyAvatarPainter(
            frame: _frame,
            palette: widget.palette,
            outfit:
                widget.palette == PortyAvatarPalette.brand
                    ? widget.outfit ?? PortyOutfitScope.of(context)
                    : PortyOutfit.none,
          ),
        ),
      ),
    );
    if (widget.onTap != null) {
      avatar = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTap,
        child: avatar,
      );
    }
    return avatar;
  }
}

@immutable
class _Pose {
  const _Pose({
    this.dy = 0,
    this.rotation = 0,
    this.scale = 1,
    this.opacity = 1,
  });

  static const rest = _Pose();

  final double dy;
  final double rotation;
  final double scale;

  /// Opacidad del cuerpo.
  final double opacity;

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
    dy: lerpDouble(a.dy, b.dy, t)!,
    rotation: lerpDouble(a.rotation, b.rotation, t)!,
    scale: lerpDouble(a.scale, b.scale, t)!,
    opacity: lerpDouble(a.opacity, b.opacity, t)!,
  );
}

/// Pinta un [PortyFrame] con la geometría de los SVG. La caja es de
/// [boxUnits] unidades centrada en el cuerpo (x/y 7–57 del SVG), con margen
/// para el destello (que llega a y = −4) y el movimiento.
class PortyAvatarPainter extends CustomPainter {
  PortyAvatarPainter({
    required this.frame,
    required this.palette,
    this.outfit = PortyOutfit.none,
  });

  final PortyFrame frame;
  final PortyAvatarPalette palette;
  final PortyOutfit outfit;

  static const boxUnits = 72.0;
  static const _boxOrigin = -4.0;
  static const _center = Offset(32, 32);
  static const _sparkCenter = Offset(60, 2);

  /// Compensación óptica: a [smallSize] px lógicos o menos, el trazo de las
  /// bocas engorda [smallStrokeBoost] unidades para que no se pierda.
  static const smallSize = 24.0;
  static const smallStrokeBoost = 0.6;

  static final Path _body =
      Path()
        ..moveTo(33, 7)
        ..cubicTo(47, 7, 57, 17, 57, 32)
        ..cubicTo(57, 47, 47, 57, 31, 57)
        ..cubicTo(16, 57, 7, 48, 7, 34)
        ..cubicTo(7, 18, 18, 7, 33, 7)
        ..close();

  static final Path _spark =
      Path()
        ..moveTo(60, -4)
        ..quadraticBezierTo(61, 1, 66, 2)
        ..quadraticBezierTo(61, 3, 60, 8)
        ..quadraticBezierTo(59, 3, 54, 2)
        ..quadraticBezierTo(59, 1, 60, -4)
        ..close();

  static final PathMetric _smile =
      (Path()
            ..moveTo(26, 39)
            ..quadraticBezierTo(33, 45, 42, 37))
          .computeMetrics()
          .first;

  /// Arco suave hacia abajo, centrado como las otras bocas: apenas triste.
  static final PathMetric _frown =
      (Path()
            ..moveTo(29, 42.5)
            ..quadraticBezierTo(33.5, 38.5, 38, 42.5))
          .computeMetrics()
          .first;

  /// Sonrisa leve de reposo.
  static final Path _restSmile =
      Path()
        ..moveTo(29.6, 40)
        ..quadraticBezierTo(33.6, 43, 38.6, 38.6);

  /// Boca chica, corrida hacia donde miran los ojos al pensar.
  static final Path _thinkMouth =
      Path()
        ..moveTo(33.4, 40.2)
        ..quadraticBezierTo(36.4, 41.8, 39.4, 40);

  static final Path _flatMouth =
      Path()
        ..moveTo(30, 41.5)
        ..lineTo(38, 41.5);

  /// Ojos de cada estado: (cx izquierdo, cy, r); el derecho está 12 a la
  /// derecha.
  static (double, double, double) _eyes(PortyAvatarState state) =>
      switch (state) {
        PortyAvatarState.idle || PortyAvatarState.answering => (28, 30, 3.6),
        PortyAvatarState.thinking => (32, 26, 3.4),
        PortyAvatarState.answered => (28, 29, 3.6),
        PortyAvatarState.concerned => (28, 30.5, 3.4),
        PortyAvatarState.error => (28, 31, 3.1),
      };

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.opacity <= 0) return;
    final fade = frame.opacity < 1;
    if (fade) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, frame.opacity),
      );
    }
    canvas
      ..save()
      ..scale(size.width / boxUnits)
      ..translate(-_boxOrigin, -_boxOrigin);

    // Halo (pulso del chat): el glow del orbe, detrás de todo.
    if (frame.haloOpacity > 0) {
      canvas
        ..save()
        ..translate(_center.dx, _center.dy + frame.dy)
        ..scale(frame.scale)
        ..translate(-_center.dx, -_center.dy);
      for (final (alpha, blur) in const [
        (PortyAvatarMotion.haloOuterAlpha, PortyAvatarMotion.haloOuterBlur),
        (PortyAvatarMotion.haloInnerAlpha, PortyAvatarMotion.haloInnerBlur),
      ]) {
        canvas.drawPath(
          _body,
          Paint()
            ..color = palette.body.withValues(
              alpha: palette.body.a * alpha * frame.haloOpacity,
            )
            // Mismo blur que el BoxShadow del orbe (radio → sigma).
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              blur * 0.57735 + 0.5,
            ),
        );
      }
      canvas.restore();
    }

    // Eco (pulso del chat): el contorno del cuerpo, plano, por detrás.
    if (frame.echoOpacity > 0) {
      canvas
        ..save()
        ..translate(_center.dx, _center.dy + frame.dy)
        ..scale(frame.echoScale)
        ..translate(-_center.dx, -_center.dy)
        ..drawPath(
          _body,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = PortyAvatarMotion.echoStrokeWidth / frame.echoScale
            ..color = palette.body.withValues(
              alpha: palette.body.a * frame.echoOpacity,
            ),
        )
        ..restore();
    }

    // El cuerpo y la cara se mueven juntos alrededor del centro del cuerpo.
    canvas
      ..save()
      ..translate(_center.dx, _center.dy + frame.dy)
      ..rotate(frame.rotation)
      ..scale(frame.scale)
      ..translate(-_center.dx, -_center.dy)
      ..drawPath(
        _body,
        Paint()
          ..color = palette.body.withValues(
            alpha: palette.body.a * frame.bodyOpacity,
          ),
      );
    final from = frame.from;
    final boost = size.width <= smallSize ? smallStrokeBoost : 0.0;
    // [PortyFrame.smile] es el trazado del estado nuevo: la boca que se va
    // ya estaba entera y se funde así, sin desaparecer de golpe.
    if (from != null) {
      _layer(canvas, from, 1 - frame.crossfade, smile: 1, boost: boost);
    }
    _layer(
      canvas,
      frame.state,
      from == null ? 1 : frame.crossfade,
      smile: frame.smile,
      boost: boost,
    );
    if (!outfit.isEmpty) PortyAccessoryPainter.paintBody(canvas, outfit);
    canvas.restore();

    // El destello no se mueve con el cuerpo: titila en su lugar.
    if (frame.spark && from == PortyAvatarState.thinking) {
      _paintSpark(canvas, 1 - frame.crossfade);
    }
    if (frame.spark && frame.state == PortyAvatarState.thinking) {
      _paintSpark(canvas, from == null ? 1 : frame.crossfade);
    }
    canvas.restore();
    if (fade) canvas.restore();
  }

  void _layer(
    Canvas canvas,
    PortyAvatarState state,
    double alpha, {
    required double smile,
    required double boost,
  }) {
    if (alpha <= 0) return;
    if (alpha >= 1) {
      _features(canvas, state, smile: smile, boost: boost);
      return;
    }
    // Capa propia: los ojos de los dos estados se funden sin oscurecerse
    // donde se superponen.
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    _features(canvas, state, smile: smile, boost: boost);
    canvas.restore();
  }

  void _features(
    Canvas canvas,
    PortyAvatarState state, {
    required double smile,
    required double boost,
  }) {
    final fill = Paint()..color = palette.features;
    final (cx, cy, r) = _eyes(state);
    final eyeHeight = 2 * r * (1 - 0.9 * frame.blink);
    final look = frame.eyeOffset;
    for (final x in [cx, cx + 12]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, cy) + look,
          width: 2 * r,
          height: eyeHeight,
        ),
        fill,
      );
    }
    if (!outfit.isEmpty) {
      PortyAccessoryPainter.paintFace(canvas, outfit, Offset(cx, cy) + look, r);
    }

    final stroke =
        Paint()
          ..color = palette.features
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2 + boost
          ..strokeCap = StrokeCap.round;
    switch (state) {
      case PortyAvatarState.answering:
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(34.1, 40.5),
            width: 5.2,
            height: 4 * frame.mouthScale,
          ),
          fill,
        );
      case PortyAvatarState.answered:
        if (smile > 0) {
          canvas.drawPath(_smile.extractPath(0, _smile.length * smile), stroke);
        }
      case PortyAvatarState.concerned:
        if (smile > 0) {
          canvas.drawPath(
            _frown.extractPath(0, _frown.length * smile),
            stroke..strokeWidth = 2.8 + boost,
          );
        }
      case PortyAvatarState.error:
        canvas.drawPath(_flatMouth, stroke);
      case PortyAvatarState.idle:
        canvas.drawPath(_restSmile, stroke);
      case PortyAvatarState.thinking:
        canvas.drawPath(_thinkMouth, stroke);
    }
  }

  void _paintSpark(Canvas canvas, double alpha) {
    final glow = (alpha * frame.sparkGlow).clamp(0.0, 1.0);
    if (glow <= 0) return;
    final grow = 0.8 + 0.2 * frame.sparkGlow;
    canvas
      ..save()
      ..translate(_sparkCenter.dx, _sparkCenter.dy)
      ..scale(grow)
      ..translate(-_sparkCenter.dx, -_sparkCenter.dy)
      ..drawPath(
        _spark,
        Paint()
          ..color = palette.spark.withValues(alpha: palette.spark.a * glow),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(PortyAvatarPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.palette != palette ||
      oldDelegate.outfit != outfit;
}

/// El destello de Porty (el de [PortyAvatarState.thinking]) como glifo
/// suelto, en lugar del sparkle de Material: marca chips de sugerencias,
/// avisos de cortesía y tips, donde la cara entera no se leería.
class PortySpark extends StatelessWidget {
  const PortySpark({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _PortySparkPainter(color)),
  );
}

class _PortySparkPainter extends CustomPainter {
  _PortySparkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // El destello ocupa x 54–66 / y −4–8 en el SVG.
    canvas
      ..scale(size.width / 12)
      ..translate(-54, 4)
      ..drawPath(PortyAvatarPainter._spark, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PortySparkPainter oldDelegate) =>
      oldDelegate.color != color;
}

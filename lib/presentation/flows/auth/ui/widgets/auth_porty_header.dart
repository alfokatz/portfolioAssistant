import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/typewriter_text.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_through_switcher.dart';

/// `true` una vez que el saludo del login se tipeó en esta sesión de la app:
/// volver al login (ej. tras cerrar sesión) lo muestra ya escrito.
/// Global (no autoDispose) a propósito: tiene que sobrevivir a la pantalla.
final authGreetingPlayedProvider = StateProvider<bool>((ref) => false);

/// Porty arriba del login: el mismo avatar del header del chat, más grande,
/// con su nombre, una línea de qué es y un saludo con la forma de una
/// respuesta suya en el chat (texto suelto, sin burbuja).
///
/// [compact] (teclado abierto) achica el avatar y esconde la línea y el
/// saludo, para que los campos y el botón entren sin scroll en un iPhone
/// chico.
class AuthPortyHeader extends ConsumerStatefulWidget {
  const AuthPortyHeader({
    super.key,
    required this.isSignUpMode,
    this.compact = false,
  });

  final bool isSignUpMode;
  final bool compact;

  static const avatarSize = 60.0;
  static const compactAvatarSize = 32.0;

  static const entranceDuration = Duration(milliseconds: 240);
  static const compactDuration = Duration(milliseconds: 220);

  /// El typewriter arranca cuando el avatar ya casi entró.
  static const greetingDelay = Duration(milliseconds: 160);

  /// Duración total del tipeo del saludo, sea cual sea su largo: rápido, que
  /// se lea como Porty hablando y no como una espera (< 1 s con el delay).
  static const greetingTypeDuration = Duration(milliseconds: 700);

  static const greetingKey = ValueKey('auth_porty_greeting');

  @override
  ConsumerState<AuthPortyHeader> createState() => _AuthPortyHeaderState();
}

class _AuthPortyHeaderState extends ConsumerState<AuthPortyHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AuthPortyHeader.entranceDuration,
  );

  /// Si esta pantalla tipea el saludo. Se decide una vez al montar.
  late final bool _typeGreeting = !ref.read(authGreetingPlayedProvider);
  bool _greetingPlay = false;
  Timer? _greetingTimer;

  /// Solo se tipea el saludo de la pestaña con la que abrió la pantalla; al
  /// cambiar de pestaña el otro aparece entero con el fade through.
  late final bool _initialSignUp = widget.isSignUpMode;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion || !_typeGreeting) {
      _entrance.value = 1;
      _greetingPlay = true;
    } else {
      _entrance.forward();
      _greetingTimer = Timer(AuthPortyHeader.greetingDelay, () {
        if (mounted) setState(() => _greetingPlay = true);
      });
    }
    if (_typeGreeting) {
      // Marcarlo después del frame: un provider no se modifica en medio de
      // un build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(authGreetingPlayedProvider.notifier).state = true;
      });
    }
  }

  @override
  void dispose() {
    _greetingTimer?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : AuthPortyHeader.compactDuration;
    final compact = widget.compact;
    final curved = CurvedAnimation(
      parent: _entrance,
      curve: Curves.easeOutCubic,
    );

    final identity = Row(
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              end:
                  compact
                      ? AuthPortyHeader.compactAvatarSize
                      : AuthPortyHeader.avatarSize,
            ),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (context, size, _) => PortyAvatar(size: size),
          ),
        ),
        const SizedBox(width: AppDimens.sp12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: duration,
                curve: Curves.easeOutCubic,
                style: (tt.titleLarge ?? const TextStyle()).copyWith(
                  fontSize: compact ? 17 : 24,
                  fontWeight: compact ? FontWeight.w600 : FontWeight.w700,
                  height: 1.2,
                  letterSpacing: compact ? -0.25 : -0.5,
                  color: colors.textPrimary,
                ),
                child: Text('portfolio_qa_title'.tr()),
              ),
              _Collapsible(
                collapsed: compact,
                duration: duration,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppDimens.sp2),
                  child: Text(
                    'auth_porty_tagline'.tr(),
                    style: tt.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final greetingStyle = tt.bodyLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w500,
      height: 1.4,
      letterSpacing: -0.2,
      color: colors.textPrimary,
    );

    Widget greetingFor(String key, {required bool typed}) {
      final text = key.tr();
      if (!typed) return Text(text, style: greetingStyle);
      // El texto completo invisible reserva el alto final: mientras se tipea,
      // el formulario de abajo no baja línea por línea.
      return Stack(
        children: [
          Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Text(text, style: greetingStyle),
          ),
          TypewriterText(
            text: text,
            style: greetingStyle,
            play: _greetingPlay,
            charsPerSecond:
                text.length /
                (AuthPortyHeader.greetingTypeDuration.inMilliseconds / 1000),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeTransition(opacity: curved, child: identity),
        _Collapsible(
          collapsed: compact,
          duration: duration,
          child: Padding(
            padding: const EdgeInsets.only(top: AppDimens.sp24),
            child: KeyedSubtree(
              key: AuthPortyHeader.greetingKey,
              child: FadeThroughSwitcher(
                index: widget.isSignUpMode ? 1 : 0,
                builders: [
                  (_) => greetingFor(
                    'auth_greeting_sign_in',
                    typed: _typeGreeting && !_initialSignUp,
                  ),
                  (_) => greetingFor(
                    'auth_greeting_sign_up',
                    typed: _typeGreeting && _initialSignUp,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Colapsa [child] a alto cero (con fade) sin desmontarlo, así el typewriter
/// y el estado del saludo sobreviven a abrir y cerrar el teclado. Oculto,
/// tampoco se lee en VoiceOver.
class _Collapsible extends StatelessWidget {
  const _Collapsible({
    required this.collapsed,
    required this.duration,
    required this.child,
  });

  final bool collapsed;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: collapsed,
      child: ClipRect(
        child: AnimatedAlign(
          alignment: AlignmentDirectional.topStart,
          heightFactor: collapsed ? 0 : 1,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: collapsed ? 0 : 1,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: child,
          ),
        ),
      ),
    );
  }
}

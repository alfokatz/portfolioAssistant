import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';

/// Raíz de la app mientras arranca (entorno, Supabase y la sesión guardada,
/// RevenueCat, preferencias): el primer frame de Flutter es [PortyLoader]
/// sobre el mismo fondo y en el mismo lugar que el splash nativo, así
/// splash → loader → app se ve continuo. Cuando [initialize] termina, pasa
/// a la app con un crossfade de [LoaderTiming.swap].
///
/// El loader se muestra sin la espera de 300 ms: continúa al splash, que ya
/// tiene a Porty en pantalla, así que no hay nada que titile.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, required this.initialize});

  /// Inicializa todo y devuelve la app lista para montar.
  final Future<Widget> Function() initialize;

  /// Fondos del splash nativo (ver `flutter_native_splash` en pubspec.yaml).
  static const lightBackground = PortfolioColors.background;
  static const darkBackground = Color(0xFF0F0F0F);

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  Widget? _app;

  @override
  void initState() {
    super.initState();
    widget.initialize().then(
      (app) {
        if (mounted) setState(() => _app = app);
      },
      onError: (Object error, StackTrace stack) {
        // Antes del arranque en dos pasos, una falla acá dejaba la app en el
        // splash; ahora queda en el loader, y el error se reporta igual.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'app bootstrap',
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ??
        View.of(
          context,
        ).platformDispatcher.accessibilityFeatures.disableAnimations;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : LoaderTiming.swap,
      switchInCurve: LoaderTiming.swapCurve,
      switchOutCurve: LoaderTiming.swapCurve,
      layoutBuilder:
          (current, previous) => Stack(
            alignment: Alignment.center,
            textDirection: TextDirection.ltr,
            children: [...previous, if (current != null) current],
          ),
      child:
          app == null
              ? const _BootLoader(key: ValueKey('boot'))
              : KeyedSubtree(key: const ValueKey('app'), child: app),
    );
  }
}

/// [PortyLoader] fuera del `MaterialApp` (todavía no existe): fondo, colores
/// y textos según el sistema, como el splash nativo.
class _BootLoader extends StatelessWidget {
  const _BootLoader({super.key});

  /// Sin traducciones cargadas todavía: el idioma del sistema, español por
  /// defecto (como la app).
  static ({String loading, String message}) _copy(Locale locale) =>
      locale.languageCode == 'en'
          ? (loading: 'Loading', message: 'Getting your portfolio ready…')
          : (loading: 'Cargando', message: 'Preparando tu cartera…');

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final dispatcher = view.platformDispatcher;
    final dark = dispatcher.platformBrightness == Brightness.dark;
    final copy = _copy(dispatcher.locale);
    return MediaQuery.fromView(
      view: view,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color:
              dark ? AppBootstrap.darkBackground : AppBootstrap.lightBackground,
          // La fuente de la app (declarada en pubspec.yaml), sin tema todavía.
          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'Plus Jakarta Sans'),
            child: PortyLoader(
              message: copy.message,
              semanticsLabel: copy.loading,
              textColor:
                  dark
                      ? CustomColors.dark.textSecondary
                      : CustomColors.light.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

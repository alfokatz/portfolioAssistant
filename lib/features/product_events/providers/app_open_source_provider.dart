import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Cómo se abrió la app (prop `source` de `app_opened`).
enum AppOpenSource {
  icon,
  widget,
  widgetQuestion('widget_question'),
  push,
  other;

  const AppOpenSource([this._wire]);

  final String? _wire;

  String get wire => _wire ?? name;
}

/// Quién abrió la app lo anota acá (el toque de un widget, una
/// notificación); `AppOpenTracker` lo lee y lo borra. Sin marca: `icon`.
final appOpenSourceProvider = StateProvider<AppOpenSource?>((ref) => null);

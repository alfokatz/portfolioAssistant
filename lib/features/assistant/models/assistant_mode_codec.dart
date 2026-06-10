import 'assistant_mode.dart';

extension AssistantModeCodec on AssistantMode {
  static AssistantMode fromQuery(String? value) => switch (value) {
    'learn' => AssistantMode.learn,
    'explore' => AssistantMode.explore,
    'invest' => AssistantMode.invest,
    'plan' => AssistantMode.plan,
    _ => AssistantMode.portfolio,
  };

  String get queryValue => name;
}

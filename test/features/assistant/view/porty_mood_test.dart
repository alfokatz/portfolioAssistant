import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_mood.dart';

void main() {
  late PortyMood mood;
  setUp(() => mood = PortyMood());
  tearDown(() => mood.dispose());

  testWidgets('a good answer keeps smiling (the answer\'s avatar)', (
    tester,
  ) async {
    mood
      ..working()
      ..speaking()
      ..doneSpeaking(goodNews: true);
    expect(mood.value, PortyAvatarState.answered);
    await tester.pump(const Duration(seconds: 30));
    expect(mood.value, PortyAvatarState.answered);
  });

  testWidgets('with answeredHold, the smile goes back to idle', (tester) async {
    final held = PortyMood(answeredHold: const Duration(seconds: 3));
    addTearDown(held.dispose);
    held
      ..speaking()
      ..doneSpeaking(goodNews: true);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(held.value, PortyAvatarState.answered);
    await tester.pump(const Duration(milliseconds: 200));
    expect(held.value, PortyAvatarState.idle);
  });

  testWidgets('bad news ends barely sad (concerned)', (tester) async {
    mood
      ..working()
      ..speaking()
      ..doneSpeaking(goodNews: false);
    expect(mood.value, PortyAvatarState.concerned);
  });

  testWidgets('finishing text when not speaking changes nothing', (
    tester,
  ) async {
    mood.doneSpeaking(goodNews: true);
    expect(mood.value, PortyAvatarState.idle);
    mood
      ..failed()
      ..doneSpeaking(goodNews: true);
    expect(mood.value, PortyAvatarState.error);
  });

  testWidgets('error stays until the next turn; a new turn replaces the '
      'smile', (tester) async {
    mood
      ..speaking()
      ..doneSpeaking(goodNews: true)
      ..working();
    await tester.pump(const Duration(seconds: 4));
    expect(mood.value, PortyAvatarState.thinking);

    mood.failed();
    await tester.pump(const Duration(seconds: 10));
    expect(mood.value, PortyAvatarState.error);
    mood.working();
    expect(mood.value, PortyAvatarState.thinking);
  });
}

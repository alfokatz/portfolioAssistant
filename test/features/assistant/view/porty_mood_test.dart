import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_mood.dart';

void main() {
  late PortyMood mood;
  setUp(() => mood = PortyMood());
  tearDown(() => mood.dispose());

  testWidgets('a good answer smiles for 3 s and goes back to idle', (
    tester,
  ) async {
    mood
      ..working()
      ..speaking()
      ..doneSpeaking(goodNews: true);
    expect(mood.value, PortyAvatarState.answered);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(mood.value, PortyAvatarState.answered);
    await tester.pump(const Duration(milliseconds: 200));
    expect(mood.value, PortyAvatarState.idle);
  });

  testWidgets('bad news goes straight to idle', (tester) async {
    mood
      ..working()
      ..speaking()
      ..doneSpeaking(goodNews: false);
    expect(mood.value, PortyAvatarState.idle);
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

  testWidgets('error stays until the next turn, which cancels a pending '
      'return to idle', (tester) async {
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

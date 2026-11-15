// El saludo de la Home cambia con la hora. Correr:
// flutter test test/presentation/flows/home/home_app_bar_greeting_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_app_bar.dart';

void main() {
  String key(int hour, {bool name = true}) =>
      HomeAppBar.greetingKey(DateTime(2026, 11, 15, hour), withName: name);

  test('buen día a la mañana, buenas tardes a la tarde y buenas noches', () {
    expect(key(5), 'home_greeting_morning_name');
    expect(key(12), 'home_greeting_morning_name');
    expect(key(13), 'home_greeting_afternoon_name');
    expect(key(19), 'home_greeting_afternoon_name');
    expect(key(20), 'home_greeting_night_name');
    expect(key(2), 'home_greeting_night_name');
    expect(key(9, name: false), 'home_greeting_morning');
  });
}

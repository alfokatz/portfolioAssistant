// WidgetLaunch.parse con los toques nuevos: ítems, avisos y tamaño grande.
// Correr: flutter test test/features/home_widget/domain
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_launch.dart';

WidgetLaunch? _parse(String query) =>
    WidgetLaunch.parse(Uri.parse('porty-widget://open?homeWidget&$query'));

void main() {
  test('news item with id, rank, size and age', () {
    final l = _parse('target=news&id=9f2c41ab&rank=2&size=large&age=15')!;
    expect(l.target, WidgetLaunchTarget.news);
    expect(l.itemId, '9f2c41ab');
    expect(l.rank, 2);
    expect(l.size, 'large');
    expect(l.dataAgeMin, 15);
  });

  test('earnings item', () {
    final l = _parse('target=earnings&id=00000000&rank=4&size=medium')!;
    expect(l.target, WidgetLaunchTarget.earnings);
    expect(l.rank, 4);
  });

  test('invalid ids fall back to the app and carry no id', () {
    for (final id in ['', 'XYZ', '9F2C41AB', '9f2c41a', '9f2c41abc', '../etc']) {
      final l = _parse('target=news&id=$id&rank=1')!;
      expect(l.target, WidgetLaunchTarget.app, reason: id);
      expect(l.itemId, isNull);
    }
    expect(_parse('target=news')!.target, WidgetLaunchTarget.app);
  });

  test('rank outside 1..4 is null', () {
    expect(_parse('target=news&id=9f2c41ab&rank=0')!.rank, isNull);
    expect(_parse('target=news&id=9f2c41ab&rank=5')!.rank, isNull);
    expect(_parse('target=news&id=9f2c41ab&rank=x')!.rank, isNull);
  });

  test('teasers', () {
    expect(
      _parse('target=teaser_news&size=large')!.target,
      WidgetLaunchTarget.teaserNews,
    );
    expect(
      _parse('target=teaser_earnings&size=medium')!.target,
      WidgetLaunchTarget.teaserEarnings,
    );
    expect(WidgetLaunchTarget.teaserNews.isTeaser, isTrue);
    expect(WidgetLaunchTarget.news.isItem, isTrue);
  });

  test('size is a closed list', () {
    expect(_parse('target=app&size=huge')!.size, isNull);
    expect(_parse('target=app&size=large')!.size, 'large');
  });
}

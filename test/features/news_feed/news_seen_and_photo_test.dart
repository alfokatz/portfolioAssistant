// El punto de Noticias (por usuario, se apaga al ver el brief) y la foto
// de una nota (sin hueco si no hay o falla; solo https).
// Correr: flutter test test/features/news_feed/news_seen_and_photo_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_format.dart';
import 'package:portfolio_assistant/features/news_feed/providers/news_seen_provider.dart';
import 'package:portfolio_assistant/features/news_preferences/view/widgets/topic_grid.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NewsSeenNotifier', () {
    test(
      'remembers what a user saw, and another user does not see it',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final a = NewsSeenNotifier(preferences: prefs, userId: 'a');
        expect(a.state, isNull);
        a.markSeen(NewsSeenNotifier.markerFor('2026-11-26'));
        expect(
          NewsSeenNotifier(preferences: prefs, userId: 'a').state,
          'brief:2026-11-26',
        );
        expect(NewsSeenNotifier(preferences: prefs, userId: 'b').state, isNull);
      },
    );
  });

  group('image_url', () {
    test('parseImageUrl keeps only https with a host', () {
      expect(parseImageUrl('https://a.com/x.jpg'), 'https://a.com/x.jpg');
      for (final bad in ['http://a.com/x.jpg', 'https://', '', null, 4]) {
        expect(parseImageUrl(bad), isNull, reason: '$bad');
      }
    });

    test('BriefSource round-trips image_url', () {
      final s =
          BriefSource.tryParse({
            'title': 't',
            'source': 'Reuters',
            'url': 'https://r.com/a',
            'image_url': 'https://img.r.com/a.jpg',
          })!;
      expect(BriefSource.tryParse(s.toJson())!.imageUrl, s.imageUrl);
    });

    testWidgets('no url: no space at all', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: NewsPhoto(url: null, height: 80)),
        ),
      );
      expect(tester.getSize(find.byType(NewsPhoto)), Size.zero);
    });

    testWidgets('http url is never loaded', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: NewsPhoto(url: 'http://a.com/x.jpg', height: 80)),
        ),
      );
      expect(find.byType(Image), findsNothing);
    });
  });

  group('DailyBriefFormat', () {
    test('boldFigures bolds numbers and leaves words alone', () {
      const bold = TextStyle(fontWeight: FontWeight.w700);
      final spans = DailyBriefFormat.boldFigures('Subió 3,4 % hoy', bold);
      final boldTexts = [
        for (final s in spans)
          if ((s as TextSpan).style == bold) s.text,
      ];
      expect(boldTexts, ['3,4 %']);
    });

    test('mood follows the day', () {
      expect(DailyBriefFormat.moodOf(1).name, 'answered');
      expect(DailyBriefFormat.moodOf(-1).name, 'concerned');
      expect(DailyBriefFormat.moodOf(0.01).name, 'serious');
      expect(DailyBriefFormat.moodOf(double.nan).name, 'serious');
    });
  });

  testWidgets('TopicGrid: two per row, dark means followed', (tester) async {
    final taps = <(String, bool)>[];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: c.read(themeDataLightProvider),
        home: Scaffold(
          body: SizedBox(
            width: 335,
            child: TopicGrid(
              items: const [
                (id: 'a', label: 'Fed', followed: true),
                (id: 'b', label: 'Cripto', followed: false),
                (id: 'c', label: 'Inflación', followed: false),
              ],
              onToggle: (id, v) => taps.add((id, v)),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('Fed')).dy,
      tester.getTopLeft(find.text('Cripto')).dy,
    );
    expect(
      tester.getTopLeft(find.text('Inflación')).dy,
      greaterThan(tester.getTopLeft(find.text('Fed')).dy),
    );
    await tester.tap(find.text('Cripto'));
    expect(taps, [('b', true)]);
  });
}

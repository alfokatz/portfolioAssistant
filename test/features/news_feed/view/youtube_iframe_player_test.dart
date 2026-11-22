import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/youtube_iframe_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

YoutubeWebResourceError _error({required int code, bool? mainFrame}) =>
    YoutubeWebResourceError(
      errorCode: code,
      description: 'test',
      isForMainFrame: mainFrame,
    );

void main() {
  group('YoutubeIframePlayer.isFatalLoadError', () {
    test('a failed main document means the video cannot play', () {
      expect(
        YoutubeIframePlayer.isFatalLoadError(
          _error(code: -1009, mainFrame: true),
        ),
        isTrue,
      );
    });

    test('secondary resources (ads, metrics) do not count (iOS)', () {
      expect(
        YoutubeIframePlayer.isFatalLoadError(
          _error(code: -1003, mainFrame: false),
        ),
        isFalse,
      );
      expect(
        YoutubeIframePlayer.isFatalLoadError(_error(code: -1003)),
        isFalse,
      );
    });

    test('a cancelled request (-999) is not a failure', () {
      expect(
        YoutubeIframePlayer.isFatalLoadError(
          _error(code: -999, mainFrame: true),
        ),
        isFalse,
      );
    });
  });
}

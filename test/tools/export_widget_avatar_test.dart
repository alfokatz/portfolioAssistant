// Exporta las 3 caras de Porty (idle, answered/contenta, concerned/preocupada) como PNG para el widget nativo
// (iOS: Assets.xcassets de la extensión; Android: drawable-nodpi). No corre en
// la suite normal (escribe PNGs en ios/ y android/); se corre a mano y se
// commitean los PNG:
//
//   RUN_WIDGET_AVATAR=1 flutter test test/tools/export_widget_avatar_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';

final _enabled = Platform.environment['RUN_WIDGET_AVATAR'] == '1';

/// Lado del avatar en puntos (iOS) / dp (Android).
const _pt = 40.0;
const _iosDir = 'ios/PortyWidget/Assets.xcassets';
const _androidLight = 'android/app/src/main/res/drawable-nodpi';
const _androidNight = 'android/app/src/main/res/drawable-night-nodpi';

Future<void> _write(
  String path,
  double px,
  PortyAvatarPalette palette,
  PortyAvatarState state,
) async {
  final recorder = ui.PictureRecorder();
  PortyAvatarPainter(
    frame: PortyFrame.still(state),
    palette: palette,
  ).paint(Canvas(recorder), Size.square(px));
  final image = await recorder.endRecording().toImage(px.round(), px.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// (estado, sufijo del imageset de iOS, sufijo del drawable de Android).
const _faces = [
  (PortyAvatarState.idle, '', ''),
  (PortyAvatarState.answered, 'Happy', '_happy'),
  (PortyAvatarState.concerned, 'Concerned', '_concerned'),
];

void main() {
  test('exports the three avatar faces for the native widgets', () async {
    for (final (state, iosSuffix, androidSuffix) in _faces) {
      final iosSet = '$_iosDir/PortyAvatar$iosSuffix.imageset';
      // iOS: 1x-3x, claro y oscuro (variante por apariencia en el imageset).
      for (final scale in [1, 2, 3]) {
        await _write(
          '$iosSet/avatar@${scale}x.png',
          _pt * scale,
          PortyAvatarPalette.brand,
          state,
        );
        await _write(
          '$iosSet/avatar_dark@${scale}x.png',
          _pt * scale,
          PortyAvatarPalette.brandDark,
          state,
        );
      }
      File('$iosSet/Contents.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'images': [
            for (final scale in [1, 2, 3]) ...[
              {'idiom': 'universal', 'filename': 'avatar@${scale}x.png', 'scale': '${scale}x'},
              {
                'idiom': 'universal',
                'appearances': [
                  {'appearance': 'luminosity', 'value': 'dark'},
                ],
                'filename': 'avatar_dark@${scale}x.png',
                'scale': '${scale}x',
              },
            ],
          ],
          'info': {'author': 'xcode', 'version': 1},
        })}\n',
      );

      // Android: un solo PNG a 3x (xxhdpi) en nodpi; el de noche va aparte.
      await _write(
        '$_androidLight/porty_widget_avatar$androidSuffix.png',
        _pt * 3,
        PortyAvatarPalette.brand,
        state,
      );
      await _write(
        '$_androidNight/porty_widget_avatar$androidSuffix.png',
        _pt * 3,
        PortyAvatarPalette.brandDark,
        state,
      );
    }
  }, skip: !_enabled);
}

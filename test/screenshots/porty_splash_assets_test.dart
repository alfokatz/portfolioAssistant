// Genera las imágenes del splash nativo con el mismo painter de Porty que usa
// la app, así el splash y el `PortyLoader` coinciden píxel a píxel. No corre
// en la suite normal (escribe PNGs en assets/):
//
//   RUN_SPLASH_ASSETS=1 flutter test test/screenshots/porty_splash_assets_test.dart
//   dart run flutter_native_splash:create
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';

final _enabled = Platform.environment['RUN_SPLASH_ASSETS'] == '1';
const _out = 'assets/porty-avatar/splash';

/// flutter_native_splash espera las imágenes a 4x.
const _scale = 4.0;

Future<void> _write(String name, int canvasPx) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const box = PortyLoader.defaultSize * _scale;
  final inset = (canvasPx - box) / 2;
  canvas.translate(inset, inset);
  PortyAvatarPainter(
    frame: const PortyFrame.still(PortyAvatarState.idle),
    palette: PortyAvatarPalette.brand,
  ).paint(canvas, const Size.square(box));
  final image = await recorder.endRecording().toImage(canvasPx, canvasPx);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File('$_out/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('writes the native splash images', () async {
    // iOS / Android < 12: la caja del loader (64 dp) a 4x.
    await _write('porty_splash.png', (PortyLoader.defaultSize * _scale).round());
    // Android 12+: lienzo de 1152 px (288 dp a 4x), Porty en el centro con
    // el mismo tamaño en dp.
    await _write('porty_splash_android12.png', 1152);
  }, skip: !_enabled);
}

import 'dart:typed_data';
import 'dart:ui' as ui;

/// Achica una captura antes de mandarla a `statement-import`: la de un
/// iPhone grande pasa los 2 MB en PNG, y para leer la lista de posiciones
/// alcanza con [maxWidth] de ancho. Sin dependencias: `dart:ui` decodifica
/// (PNG, JPEG, WebP, y HEIC en iOS) y vuelve a codificar en PNG.
abstract final class ScreenshotShrinker {
  static const maxWidth = 1080;

  /// Lo que ya es chico y angosto se manda tal cual.
  static const _keepBelowBytes = 900 * 1024;

  static Future<Uint8List> shrink(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      if (width <= maxWidth && bytes.length <= _keepBelowBytes) {
        descriptor.dispose();
        buffer.dispose();
        return bytes;
      }
      final codec = await descriptor.instantiateCodec(
        targetWidth: width > maxWidth ? maxWidth : width,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return data?.buffer.asUint8List() ?? bytes;
    } catch (_) {
      // Si no se puede decodificar, que lo diga el servidor (tipo no
      // soportado) en vez de fallar acá.
      return bytes;
    }
  }
}

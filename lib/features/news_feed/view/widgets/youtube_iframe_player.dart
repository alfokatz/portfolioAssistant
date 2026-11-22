import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// El reproductor oficial de YouTube (IFrame Player API) dentro de la app.
///
/// Políticas de YouTube: controles y marca visibles (no se ocultan ni se
/// tapan), sin bloquear anuncios ni tocar el contenido, y se manda el
/// `origin` / `widget_referrer` del embebedor (lo que pide YouTube para no
/// devolver el error 153 en las WebView de Android).
///
/// Cualquier error del reproductor (video no embebible, borrado, 153…) llama
/// a [onError] y la hoja cae al enlace "Ver en YouTube". Falta confirmar en
/// un Android real que no aparezca el 153 con este `origin`.
class YoutubeIframePlayer extends StatefulWidget {
  const YoutubeIframePlayer({
    super.key,
    required this.videoId,
    required this.language,
    required this.onError,
  });

  final String videoId;

  /// `es` | `en`: idioma de la interfaz y de los subtítulos del reproductor.
  final String language;
  final VoidCallback onError;

  /// El embebedor. Es un host de YouTube a propósito: la 5.x del paquete lo
  /// usa también como `host` del iframe y uno propio rompería la carga. Al
  /// subir a 6.x (Flutter 3.47+) se pasa a un identificador de la app
  /// (`https://com.portyassistant.app`).
  static const origin = 'https://www.youtube.com';

  /// Si un error de carga del WebView significa que el video no se puede
  /// ver. Solo el documento principal: en iOS el WebView reporta como
  /// errores los recursos secundarios del reproductor (publicidad, métricas)
  /// y los pedidos cancelados (-999), y tratarlos como falla mandaba todos
  /// los videos a "Ver en YouTube". Los errores del video en sí (no
  /// embebible, borrado) llegan por el estado del reproductor.
  static bool isFatalLoadError(YoutubeWebResourceError error) =>
      error.isForMainFrame == true && error.errorCode != -999;

  @override
  State<YoutubeIframePlayer> createState() => _YoutubeIframePlayerState();
}

class _YoutubeIframePlayerState extends State<YoutubeIframePlayer> {
  late final YoutubePlayerController _controller;
  var _failed = false;

  void _fail() {
    if (_failed) return;
    _failed = true;
    if (mounted) widget.onError();
  }

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      params: YoutubePlayerParams(
        origin: YoutubeIframePlayer.origin,
        showControls: true,
        showFullscreenButton: true,
        interfaceLanguage: widget.language,
        captionLanguage: widget.language,
        strictRelatedVideos: true,
      ),
      onWebResourceError: (error) {
        if (YoutubeIframePlayer.isFatalLoadError(error)) _fail();
      },
    );
    _controller.cueVideoById(videoId: widget.videoId);
    _controller.listen((value) {
      if (value.error != YoutubeError.none) _fail();
    });
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YoutubePlayer(
    controller: _controller,
    aspectRatio: 16 / 9,
    enableFullScreenOnVerticalDrag: false,
  );
}

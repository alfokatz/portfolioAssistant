import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';

/// Carga de pantalla completa de `ContentStateWidget`: Porty pensando (ver
/// [PortyLoader]), nunca un spinner.
class Loading extends StatelessWidget {
  const Loading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: PortyLoader(message: message),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';

/// El único spinner de la app: dentro de un botón o un campo mientras corre
/// una acción puntual (guardar, comprar, entrar). 20 px y trazo 2 en un
/// botón (DESIGN.md → Buttons); [ButtonSpinner.small] en un campo.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key, required this.color})
    : size = 20,
      strokeWidth = 2;

  const ButtonSpinner.small({super.key, required this.color})
    : size = 16,
      strokeWidth = 1.75;

  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        strokeCap: StrokeCap.round,
        color: color,
      ),
    );
  }
}

/// Contenido de un botón con acción: el [label] o, mientras [loading] (con
/// las reglas de 300 ms / 400 ms de [DelayedLoaderVisibility]), el spinner
/// en su lugar. El label sigue ocupando su espacio, invisible, así el botón
/// nunca cambia de tamaño.
///
/// [builder] recibe `showSpinner` para que el botón se vea deshabilitado
/// recién cuando aparece el spinner (antes, solo ignora los toques): en una
/// acción rápida el botón no titila.
class LoadingButtonContent extends StatelessWidget {
  const LoadingButtonContent({
    super.key,
    required this.loading,
    required this.label,
    required this.spinnerColor,
    this.builder,
  });

  final bool loading;
  final Widget label;
  final Color spinnerColor;
  final Widget Function(BuildContext context, bool showSpinner, Widget child)?
  builder;

  @override
  Widget build(BuildContext context) {
    return DelayedLoaderVisibility(
      loading: loading,
      builder: (context, showSpinner) {
        final child = Stack(
          alignment: Alignment.center,
          children: [
            Visibility(
              visible: !showSpinner,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: label,
            ),
            if (showSpinner)
              Semantics(
                label: 'loading'.tr(),
                child: ButtonSpinner(color: spinnerColor),
              ),
          ],
        );
        return builder?.call(context, showSpinner, child) ?? child;
      },
    );
  }
}

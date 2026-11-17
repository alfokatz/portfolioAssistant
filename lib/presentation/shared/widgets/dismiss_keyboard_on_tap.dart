import 'package:flutter/material.dart';

/// Tocar afuera de un campo de texto baja el teclado, en toda la app.
///
/// En iOS el teclado numérico (montos, cantidades, precios) no tiene tecla
/// para cerrarlo, y en Flutter tocar afuera de un campo no le saca el foco en
/// el celular: el teclado quedaba tapando la pantalla. Va una sola vez en el
/// `builder` de la app (ver `main.dart`), así cubre cada campo, actual o
/// futuro, sin acordarse de ponerle `onTapOutside`.
///
/// Solo reacciona a un toque que no reclamó nadie: un botón, una fila o el
/// mismo campo ganan el gesto y se comportan como siempre; tocar el fondo, un
/// texto o un espacio vacío baja el teclado. Scrollear no lo baja.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  static void _dismiss() {
    final focus = FocusManager.instance.primaryFocus;
    // Solo si lo enfocado es un campo de texto: no tocar el foco de otras
    // cosas (navegación por teclado, lectores de pantalla).
    final editing =
        focus?.context?.findAncestorStateOfType<EditableTextState>() != null;
    if (editing) focus!.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _dismiss,
      excludeFromSemantics: true,
      child: child,
    );
  }
}

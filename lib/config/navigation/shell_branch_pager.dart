import 'package:flutter/material.dart';

/// Contenedor de las pestañas del shell: se pasa de una a otra deslizando el
/// dedo, como en Instagram, y tocar la barra de abajo salta directo.
///
/// - Cada pestaña sigue viva al salir (go_router ya envuelve cada navigator
///   en un keep-alive): el scroll, el estado y el chat no se pierden.
/// - Deslizar: al pasar la mitad, [onPageSwiped] cambia de rama, así la
///   barra, el FAB y la URL acompañan. Una pestaña que todavía no se abrió se
///   carga en ese momento (no se precargan: el arranque no paga de más).
/// - Tocar la barra: salto sin recorrer las del medio, con la entrada corta
///   de siempre (cae y se asienta). Deslizar no la repite: el gesto ya es
///   el movimiento.
/// - Sin rebote en los bordes, y lo de adentro que también se arrastra en
///   horizontal (gráficos, filas que se borran deslizando, chips con scroll)
///   gana el gesto.
class ShellBranchPager extends StatefulWidget {
  const ShellBranchPager({
    super.key,
    required this.currentIndex,
    required this.onPageSwiped,
    required this.children,
  });

  final int currentIndex;
  final ValueChanged<int> onPageSwiped;
  final List<Widget> children;

  @override
  State<ShellBranchPager> createState() => _ShellBranchPagerState();
}

class _ShellBranchPagerState extends State<ShellBranchPager>
    with SingleTickerProviderStateMixin {
  late final PageController _pages = PageController(
    initialPage: widget.currentIndex,
  );
  late final AnimationController _dropIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final Animation<double> _drop = Tween<double>(
    begin: -_dropDistance,
    end: 0,
  ).animate(CurvedAnimation(parent: _dropIn, curve: Curves.easeOutBack));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _dropIn,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
  );

  /// La página en la que está (o hacia la que va) el PageView.
  late int _page = widget.currentIndex;
  bool _started = false;

  static const _dropDistance = 32.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La primera entrada al shell también cae; `MediaQuery` no se puede leer
    // en initState.
    if (_started) return;
    _started = true;
    _playDropIn();
  }

  @override
  void didUpdateWidget(covariant ShellBranchPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si el índice nuevo es el de la página actual, vino del deslizamiento.
    // Si no, fue un toque en la barra (o una navegación desde código).
    final target = widget.currentIndex;
    if (target == _page) return;
    _page = target;
    if (_pages.hasClients) _pages.jumpToPage(target);
    _playDropIn();
  }

  void _playDropIn() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _dropIn.value = 1;
    } else {
      _dropIn.forward(from: 0);
    }
  }

  void _onPageChanged(int index) {
    if (index == _page) return;
    setState(() => _page = index);
    // El teclado del chat no sigue abierto sobre otra pestaña.
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onPageSwiped(index);
  }

  @override
  void dispose() {
    _pages.dispose();
    _dropIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pager = PageView(
      controller: _pages,
      physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
      onPageChanged: _onPageChanged,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          // Las animaciones de la pestaña que no se ve quedan quietas, como
          // con el IndexedStack de antes.
          TickerMode(enabled: i == _page, child: widget.children[i]),
      ],
    );
    return AnimatedBuilder(
      animation: _dropIn,
      child: pager,
      builder:
          (context, child) => Opacity(
            opacity: _fade.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, _drop.value),
              child: child,
            ),
          ),
    );
  }
}

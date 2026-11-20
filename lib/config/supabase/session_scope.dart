import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Raíz de Riverpod atada al usuario: cada vez que cambia el id del usuario
/// (cerrar sesión, iniciar sesión, otra cuenta) descarta el
/// [ProviderContainer] entero y monta la app con uno nuevo.
///
/// Garantía de seguridad: nada en memoria (cartera, chat, informe, plan,
/// metas…) sobrevive al cambio de cuenta, sin depender de que cada provider
/// escuche al auth. Además borra del disco las claves de `SharedPreferences`
/// que llevan el id del usuario que se fue (caché de la Home, informe…).
///
/// Un refresco de token no cambia el id y no reinicia nada.
class SessionScope extends StatefulWidget {
  const SessionScope({
    super.key,
    required this.initialUserId,
    required this.userIds,
    required this.child,
    this.overrides = const [],
    this.prefs,
  });

  /// El usuario de la sesión restaurada al arrancar (`null` sin sesión).
  final String? initialUserId;

  /// El id del usuario después de cada evento de auth (`null` sin sesión).
  final Stream<String?> userIds;

  /// Los mismos para cada contenedor nuevo (servicios ya inicializados).
  final List<Override> overrides;

  /// Para borrar las claves del usuario que se fue. `null`: no se borra.
  final SharedPreferences? prefs;

  final Widget child;

  /// Corre [action] con el contenedor nuevo, en el primer frame después del
  /// próximo cambio de usuario (ej.: el toast de "cuenta eliminada", que lo
  /// dibuja el login ya montado). Devuelve con qué cancelarlo.
  static VoidCallback runAfterRestart(
    void Function(ProviderContainer container) action,
  ) {
    _pending.add(action);
    return () => _pending.remove(action);
  }

  static final List<void Function(ProviderContainer)> _pending = [];

  /// Borra las claves que contienen [userId] (todas las cachés por usuario
  /// la llevan en el nombre). Quedan solo las marcas de "ya visto"
  /// (`*_seen*`): no son datos, y sin ellas al volver a entrar reaparecerían
  /// el diagnóstico o el aviso del informe.
  static Future<void> clearUserData(
    SharedPreferences prefs,
    String userId,
  ) async {
    if (userId.isEmpty) return;
    for (final key in prefs.getKeys().toList()) {
      if (key.contains(userId) && !key.contains('_seen')) {
        await prefs.remove(key);
      }
    }
  }

  @override
  State<SessionScope> createState() => _SessionScopeState();
}

class _SessionScopeState extends State<SessionScope> {
  late ProviderContainer _container;
  late String? _userId;
  int _generation = 0;
  StreamSubscription<String?>? _sub;

  @override
  void initState() {
    super.initState();
    _userId = widget.initialUserId;
    _container = ProviderContainer(overrides: widget.overrides);
    _sub = widget.userIds.listen(
      _onUserId,
      // Errores del stream de auth (link vencido): los muestra el login.
      onError: (Object _) {},
    );
  }

  void _onUserId(String? userId) {
    if (!mounted || userId == _userId) return;
    final previousUserId = _userId;
    final previous = _container;
    _userId = userId;
    setState(() {
      _container = ProviderContainer(overrides: widget.overrides);
      _generation++;
    });
    // Después del frame que desmonta el árbol viejo: ningún widget sigue
    // escuchando el contenedor anterior. Los eventos de auth ya le llegaron
    // (cierre de RevenueCat, limpieza del widget nativo), así que esas
    // tareas ya quedaron encoladas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previous.dispose();
      final prefs = widget.prefs;
      if (prefs != null && previousUserId != null) {
        unawaited(SessionScope.clearUserData(prefs, previousUserId));
      }
      final pending = List.of(SessionScope._pending);
      SessionScope._pending.clear();
      for (final action in pending) {
        try {
          action(_container);
        } catch (_) {}
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // La key nueva desmonta todo el árbol: ningún State (hooks, controllers,
    // scroll) del usuario anterior pasa al siguiente.
    return UncontrolledProviderScope(
      key: ValueKey(_generation),
      container: _container,
      child: widget.child,
    );
  }
}

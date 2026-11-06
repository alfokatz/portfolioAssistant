import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';

/// App Group de iOS donde la app y la extensión comparten el snapshot.
const homeWidgetAppGroupId = 'group.com.portyassistant.app';

/// Nombre (kind) del widget en iOS.
const homeWidgetIosKind = 'PortyWidget';

/// Providers de Android. El paquete de Kotlin (`com.portfolioassistant.app`)
/// no es el applicationId (`com.portyassistant.app` + sufijo del flavor):
/// por eso se pasa el nombre calificado completo.
const homeWidgetAndroidSmall =
    'com.portfolioassistant.app.widget.PortySmallWidgetProvider';
const homeWidgetAndroidMedium =
    'com.portfolioassistant.app.widget.PortyMediumWidgetProvider';
const homeWidgetAndroidLarge =
    'com.portfolioassistant.app.widget.PortyLargeWidgetProvider';

/// Clave compartida donde el nativo anota qué dibujó (solo conteos, nunca
/// tickers). Es lo único que escribe el nativo.
const homeWidgetRenderLogKey = 'porty_widget_render_log';

/// Clave compartida donde el nativo guarda qué novedad muestra el mediano
/// (`{"rev","index","at"}`). Solo la escribe el nativo; Dart la borra al
/// cerrar sesión.
const homeWidgetCursorKey = 'porty_widget_cursor';

/// Los tamaños de widget que hay instalados: `small`, `medium` y/o `large`.
typedef InstalledWidgetSizes = List<String>;

/// Envoltorio inyectable de `home_widget`: es lo único de la app que habla
/// con el plugin (los tests usan un fake).
abstract class HomeWidgetStore {
  /// 'ios' | 'android' (para los eventos).
  String get platform;

  /// Guarda el JSON del snapshot y le pide al sistema que redibuje.
  Future<void> writeSnapshot(WidgetSnapshot snapshot);

  /// Pasa a la forma oculta el snapshot `ready` ya guardado (sin tickers,
  /// titulares ni preguntas). Sirve para "Ocultar posiciones" cuando no hay
  /// datos frescos para reescribirlo.
  Future<void> scrubStoredPositions();

  /// Lo que el nativo dibujó la última vez (`porty_widget_render_log`), o
  /// `null` si no hay o no se puede leer.
  Future<Map<String, Object?>?> readRenderLog();

  /// Borra el render log (cierre de sesión).
  Future<void> clearRenderLog();

  /// El cursor del mediano (`porty_widget_cursor`), o `null`.
  Future<Map<String, Object?>?> readCursor();

  /// Borra el cursor del mediano (cierre de sesión).
  Future<void> clearCursor();

  /// Los tamaños instalados, ordenados y sin repetir.
  Future<InstalledWidgetSizes> installedSizes();

  /// El snapshot que el widget está dibujando (JSON guardado), o `null` si
  /// no hay o no se puede leer. Solo para la vista previa de la oferta.
  Future<Map<String, Object?>?> readSnapshotJson();

  /// Android: si el launcher deja pedir que se agregue el widget mediano.
  Future<bool> isPinSupported();

  /// Android: le pide al launcher que agregue el widget mediano (el sistema
  /// muestra su propia confirmación).
  Future<void> requestPin();

  /// La URL con la que se abrió la app desde el widget (cold start).
  Future<Uri?> initialLaunch();

  /// Toques del widget con la app viva.
  Stream<Uri?> get launches;
}

class PluginHomeWidgetStore implements HomeWidgetStore {
  const PluginHomeWidgetStore();

  @override
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<void> writeSnapshot(WidgetSnapshot snapshot) async {
    await HomeWidget.saveWidgetData<String>(
      WidgetSnapshot.storageKey,
      jsonEncode(snapshot.toJson()),
    );
    await _update();
  }

  @override
  Future<void> scrubStoredPositions() async {
    final raw = await HomeWidget.getWidgetData<String>(
      WidgetSnapshot.storageKey,
    );
    if (raw == null) return;
    final json = scrubPositionsFromSnapshotJson(
      jsonDecode(raw) as Map<String, Object?>,
    );
    if (json == null) return;
    await HomeWidget.saveWidgetData<String>(
      WidgetSnapshot.storageKey,
      jsonEncode(json),
    );
    await _update();
  }

  @override
  Future<Map<String, Object?>?> readRenderLog() async {
    try {
      final raw = await HomeWidget.getWidgetData<String>(
        homeWidgetRenderLogKey,
      );
      if (raw == null) return null;
      final json = jsonDecode(raw);
      return json is Map ? Map<String, Object?>.from(json) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearRenderLog() async {
    try {
      await HomeWidget.saveWidgetData<String>(homeWidgetRenderLogKey, null);
    } catch (_) {}
  }

  @override
  Future<Map<String, Object?>?> readCursor() async {
    try {
      final raw = await HomeWidget.getWidgetData<String>(homeWidgetCursorKey);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      return json is Map ? Map<String, Object?>.from(json) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearCursor() async {
    try {
      await HomeWidget.saveWidgetData<String>(homeWidgetCursorKey, null);
    } catch (_) {}
  }

  Future<void> _update() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.updateWidget(iOSName: homeWidgetIosKind);
      return;
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: homeWidgetAndroidSmall);
    await HomeWidget.updateWidget(
      qualifiedAndroidName: homeWidgetAndroidMedium,
    );
    await HomeWidget.updateWidget(qualifiedAndroidName: homeWidgetAndroidLarge);
  }

  @override
  Future<InstalledWidgetSizes> installedSizes() async {
    final infos = await HomeWidget.getInstalledWidgets();
    final sizes = <String>{};
    for (final info in infos) {
      final family = info.iOSFamily?.toLowerCase();
      final cls = info.androidClassName ?? '';
      if (family != null && family.contains('small')) sizes.add('small');
      if (family != null && family.contains('medium')) sizes.add('medium');
      if (family != null && family.contains('large')) sizes.add('large');
      if (cls.endsWith('PortySmallWidgetProvider')) sizes.add('small');
      if (cls.endsWith('PortyMediumWidgetProvider')) sizes.add('medium');
      if (cls.endsWith('PortyLargeWidgetProvider')) sizes.add('large');
    }
    return sizes.toList()..sort();
  }

  @override
  Future<Map<String, Object?>?> readSnapshotJson() async {
    try {
      final raw = await HomeWidget.getWidgetData<String>(
        WidgetSnapshot.storageKey,
      );
      if (raw == null) return null;
      final json = jsonDecode(raw);
      return json is Map ? Map<String, Object?>.from(json) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isPinSupported() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) return false;
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> requestPin() => HomeWidget.requestPinWidget(
    qualifiedAndroidName: homeWidgetAndroidMedium,
  );

  @override
  Future<Uri?> initialLaunch() => HomeWidget.initiallyLaunchedFromHomeWidget();

  @override
  Stream<Uri?> get launches => HomeWidget.widgetClicked;
}

final homeWidgetStoreProvider = Provider<HomeWidgetStore>(
  (ref) => const PluginHomeWidgetStore(),
);

/// Versión con posiciones ocultas de un snapshot ya serializado, o `null`
/// si no hay nada que sacar: no es un `ready` o es de la versión anterior
/// (sin bloque `v2`; el nativo nuevo ya no muestra tickers del legado).
///
/// Los ítems del feed pasan a la forma oculta (solo `kind`, `icon`, `paid`,
/// `expires_at` y `segments` con `from`/`prio`), sin `feed_rev`, `tag` ni
/// preguntas.
Map<String, Object?>? scrubPositionsFromSnapshotJson(
  Map<String, Object?> json,
) {
  if (json['state'] != WidgetSnapshotState.ready.wire) return null;
  final v2 = json['v2'];
  if (v2 is! Map) return null;
  final feed = v2['feed'];
  final hidden = <String, Object?>{
    ...v2.cast<String, Object?>(),
    'positions_hidden': true,
    'feed': [
      if (feed is List)
        for (final item in feed)
          if (item is Map)
            {
              'kind': item['kind'],
              'icon': item['icon'],
              if (item['paid'] == true) 'paid': true,
              'expires_at': item['expires_at'],
              'segments': [
                for (final seg in (item['segments'] as List? ?? const []))
                  if (seg is Map) {'from': seg['from'], 'prio': seg['prio']},
              ],
            },
    ],
    'questions': {'fallback': null, 'large': <Object?>[]},
  }..remove('feed_rev');
  return {...json, 'v2': hidden};
}

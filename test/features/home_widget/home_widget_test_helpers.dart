// Helpers compartidos de los tests del widget de la pantalla de inicio:
// textos reales de es/en, un store falso y un scheduler falso.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_background_refresh.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_texts.dart';

/// Los textos `home_widget_*` reales, leídos de los JSON de traducciones.
WidgetTexts realTexts(String lang) {
  final file = lang == 'en' ? 'en-US' : 'es-ES';
  final json =
      jsonDecode(File('assets/translations/$file.json').readAsStringSync())
          as Map<String, Object?>;
  return WidgetTexts.fromJson(json);
}

Future<WidgetTexts> loadRealTexts(String lang) async => realTexts(lang);

class FakeHomeWidgetStore implements HomeWidgetStore {
  FakeHomeWidgetStore({List<String> installed = const ['small', 'medium']})
    : installed = [...installed];

  /// Lo que se escribió, ya como JSON (lo mismo que ve el nativo).
  final writes = <Map<String, Object?>>[];
  List<String> installed;
  Uri? initial;
  final controller = StreamController<Uri?>.broadcast();
  bool failWrites = false;

  Map<String, Object?> get last => writes.last;

  String platformName = 'ios';

  @override
  String get platform => platformName;

  @override
  Future<void> writeSnapshot(WidgetSnapshot snapshot) async {
    if (failWrites) throw StateError('write failed');
    writes.add(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>,
    );
  }

  int scrubs = 0;

  @override
  Future<void> scrubStoredPositions() async {
    scrubs++;
    if (writes.isEmpty) return;
    final scrubbed = scrubPositionsFromSnapshotJson(writes.last);
    if (scrubbed != null) writes.add(scrubbed);
  }

  /// El cursor del mediano (lo escribe el nativo).
  Map<String, Object?>? cursor;
  int cursorClears = 0;

  @override
  Future<Map<String, Object?>?> readCursor() async => cursor;

  @override
  Future<void> clearCursor() async {
    cursorClears++;
    cursor = null;
  }

  /// Lo que "dibujó el nativo" (render log).
  Map<String, Object?>? renderLog;
  int renderLogClears = 0;

  @override
  Future<Map<String, Object?>?> readRenderLog() async => renderLog;

  @override
  Future<void> clearRenderLog() async {
    renderLogClears++;
    renderLog = null;
  }

  @override
  Future<InstalledWidgetSizes> installedSizes() async => installed;

  /// Lo que lee la vista previa de la oferta (default: lo último escrito).
  Map<String, Object?>? snapshotJson;
  bool pinSupported = true;
  bool failPin = false;
  int pinRequests = 0;

  @override
  Future<Map<String, Object?>?> readSnapshotJson() async =>
      snapshotJson ?? (writes.isEmpty ? null : writes.last);

  @override
  Future<bool> isPinSupported() async => pinSupported;

  @override
  Future<void> requestPin() async {
    if (failPin) throw StateError('pin failed');
    pinRequests++;
  }

  @override
  Future<Uri?> initialLaunch() async => initial;

  @override
  Stream<Uri?> get launches => controller.stream;
}

class FakeScheduler implements WidgetBackgroundScheduler {
  int registered = 0;
  int cancelled = 0;

  @override
  Future<void> ensureRegistered() async => registered++;

  @override
  Future<void> cancel() async => cancelled++;
}

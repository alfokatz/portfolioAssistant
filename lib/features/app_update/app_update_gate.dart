import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';

/// Build mínimo soportado por plataforma (el `+N` de pubspec), con la URL
/// de tienda a la que manda "Actualizar".
class MinSupportedBuild {
  const MinSupportedBuild({required this.build, this.storeUrl});

  final int build;
  final String? storeUrl;
}

/// De dónde sale el mínimo. Hoy la fila `min_supported_build` de
/// `public.app_config` en Supabase (el proyecto no tiene Firebase
/// configurado); cambiar a Remote Config es otra implementación de esto.
abstract class MinSupportedBuildSource {
  Future<MinSupportedBuild?> fetch(TargetPlatform platform);
}

class SupabaseMinSupportedBuildSource implements MinSupportedBuildSource {
  SupabaseMinSupportedBuildSource(this._query);

  /// Devuelve el `value` jsonb de `app_config` para la key pedida.
  final Future<Map<String, dynamic>?> Function(String key) _query;

  @override
  Future<MinSupportedBuild?> fetch(TargetPlatform platform) async {
    final value = await _query('min_supported_build');
    if (value == null) return null;
    final name = platform == TargetPlatform.iOS ? 'ios' : 'android';
    final build = value[name];
    return MinSupportedBuild(
      build: build is num ? build.toInt() : 0,
      storeUrl: value['${name}_store_url'] as String?,
    );
  }
}

/// Resultado del chequeo al arrancar.
class AppUpdateStatus {
  const AppUpdateStatus({required this.required, this.storeUrl});

  static const ok = AppUpdateStatus(required: false);

  final bool required;
  final String? storeUrl;
}

/// Decide si este build quedó por debajo del mínimo. Falla ABIERTO: sin red
/// o sin respuesta en [timeout], la app sigue (un problema de conectividad
/// nunca deja a alguien afuera; el servidor igual aplica sus límites).
Future<AppUpdateStatus> checkAppUpdate({
  required MinSupportedBuildSource source,
  required Future<int> Function() currentBuild,
  required TargetPlatform platform,
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    final min = await source.fetch(platform).timeout(timeout);
    if (min == null || min.build <= 0) return AppUpdateStatus.ok;
    final build = await currentBuild();
    if (build <= 0 || build >= min.build) return AppUpdateStatus.ok;
    return AppUpdateStatus(required: true, storeUrl: min.storeUrl);
  } catch (e) {
    if (kDebugMode) debugPrint('[AppUpdate] check skipped: $e');
    return AppUpdateStatus.ok;
  }
}

final minSupportedBuildSourceProvider = Provider<MinSupportedBuildSource>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return SupabaseMinSupportedBuildSource((key) async {
    final row =
        await client
            .from('app_config')
            .select('value')
            .eq('key', key)
            .maybeSingle();
    return row?['value'] as Map<String, dynamic>?;
  });
});

final appUpdateStatusProvider = FutureProvider<AppUpdateStatus>((ref) {
  return checkAppUpdate(
    source: ref.watch(minSupportedBuildSourceProvider),
    currentBuild:
        () async =>
            int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0,
    platform: defaultTargetPlatform,
  );
});

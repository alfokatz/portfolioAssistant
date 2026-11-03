/// Qué hacer con el informe de una semana, según el servidor
/// (`claim_weekly_report`, migración 20261002120000_weekly_reports.sql).
sealed class WeeklyReportClaim {
  const WeeklyReportClaim();

  /// [raw] = respuesta de la RPC. Cualquier cosa inesperada es
  /// [ClaimUnavailable]: la app muestra los números y no genera.
  static WeeklyReportClaim parse(Object? raw) {
    if (raw is! Map) return const ClaimUnavailable();
    final courtesy = raw['courtesy'] == true;
    int? positive(Object? v) => v is int && v >= 1 ? v : null;
    return switch (raw['state']) {
      'ready' when raw['payload'] is Map => ClaimReady(
        payload: (raw['payload'] as Map).cast<String, Object?>(),
        courtesy: courtesy,
      ),
      'claimed' => ClaimGranted(
        courtesy: courtesy,
        attempt: (raw['attempt'] as num?)?.toInt() ?? 1,
        courtesyNumber: courtesy ? positive(raw['courtesy_number']) : null,
        courtesyTotal: courtesy ? positive(raw['courtesy_total']) : null,
      ),
      'in_progress' => const ClaimInProgress(),
      'numbers_only' => const ClaimNumbersOnly(),
      'failed' => const ClaimFailed(),
      'disabled' => const ClaimDisabled(),
      _ => const ClaimUnavailable(),
    };
  }
}

/// Ya está generado (por este u otro dispositivo).
class ClaimReady extends WeeklyReportClaim {
  const ClaimReady({required this.payload, required this.courtesy});
  final Map<String, Object?> payload;
  final bool courtesy;
}

/// Le toca a este dispositivo generarlo (variante completa, con Porty).
class ClaimGranted extends WeeklyReportClaim {
  const ClaimGranted({
    required this.courtesy,
    required this.attempt,
    this.courtesyNumber,
    this.courtesyTotal,
  });

  /// Degustación de alguien sin Gold: la UI lo cuenta ("tu informe de
  /// regalo").
  final bool courtesy;
  final int attempt;

  /// Cuál de los informes de regalo es ("2 de 3"). null si el servidor no lo
  /// mandó (versión anterior) o no es de regalo.
  final int? courtesyNumber;
  final int? courtesyTotal;
}

/// Otro dispositivo lo está generando: volver a preguntar en un rato.
class ClaimInProgress extends WeeklyReportClaim {
  const ClaimInProgress();
}

/// Sin Gold y con la degustación usada: solo los números, sin LLM.
class ClaimNumbersOnly extends WeeklyReportClaim {
  const ClaimNumbersOnly();
}

/// Se agotaron los intentos de generación de la semana.
class ClaimFailed extends WeeklyReportClaim {
  const ClaimFailed();
}

/// El informe está apagado desde el servidor (`app_config`): sin tarjeta.
class ClaimDisabled extends WeeklyReportClaim {
  const ClaimDisabled();
}

/// No se pudo consultar (sin red, sin sesión, semana inválida).
class ClaimUnavailable extends WeeklyReportClaim {
  const ClaimUnavailable();
}

/// Qué hacer con el brief de un día, según el servidor (`claim_daily_brief`,
/// spec 2026-11-20-brief-diario-tech.md §3.3).
sealed class DailyBriefClaim {
  const DailyBriefClaim();

  /// [raw] = respuesta de la RPC. Cualquier cosa inesperada es
  /// [BriefClaimUnavailable]: la app no muestra nada nuevo.
  static DailyBriefClaim parse(Object? raw) {
    if (raw is! Map) return const BriefClaimUnavailable();
    final courtesy = raw['courtesy'] == true;
    int? positive(Object? v) => v is int && v >= 1 ? v : null;
    return switch (raw['state']) {
      'ready' when raw['payload'] is Map => BriefClaimReady(
        payload: (raw['payload'] as Map).cast<String, Object?>(),
        courtesy: courtesy,
      ),
      'claimed' => BriefClaimGranted(
        courtesy: courtesy,
        attempt: (raw['attempt'] as num?)?.toInt() ?? 1,
        courtesyNumber: courtesy ? positive(raw['courtesy_number']) : null,
        courtesyTotal: courtesy ? positive(raw['courtesy_total']) : null,
      ),
      'numbers_only' => const BriefClaimNumbersOnly(),
      'in_progress' => const BriefClaimInProgress(),
      'failed' => const BriefClaimFailed(),
      'disabled' => const BriefClaimDisabled(),
      'no_portfolio' => const BriefClaimNoPortfolio(),
      'not_business_day' => const BriefClaimNotBusinessDay(),
      _ => const BriefClaimUnavailable(),
    };
  }
}

/// Ya está guardado (por este u otro dispositivo).
class BriefClaimReady extends DailyBriefClaim {
  const BriefClaimReady({required this.payload, required this.courtesy});
  final Map<String, Object?> payload;
  final bool courtesy;
}

/// Le toca a este dispositivo generar el brief completo (con Porty).
class BriefClaimGranted extends DailyBriefClaim {
  const BriefClaimGranted({
    required this.courtesy,
    required this.attempt,
    this.courtesyNumber,
    this.courtesyTotal,
  });
  final bool courtesy;
  final int attempt;

  /// "día 2 de 7" de la cortesía (null si no es de regalo).
  final int? courtesyNumber;
  final int? courtesyTotal;
}

/// Free sin cortesía: la app arma el brief sin LLM y lo guarda.
class BriefClaimNumbersOnly extends DailyBriefClaim {
  const BriefClaimNumbersOnly();
}

/// Otro dispositivo lo está generando.
class BriefClaimInProgress extends DailyBriefClaim {
  const BriefClaimInProgress();
}

/// Se agotaron los intentos del día.
class BriefClaimFailed extends DailyBriefClaim {
  const BriefClaimFailed();
}

/// El interruptor no cubre a este usuario: sin fila ni entrada.
class BriefClaimDisabled extends DailyBriefClaim {
  const BriefClaimDisabled();
}

/// Sin posiciones: no hay brief.
class BriefClaimNoPortfolio extends DailyBriefClaim {
  const BriefClaimNoPortfolio();
}

/// Fin de semana o fecha no plausible.
class BriefClaimNotBusinessDay extends DailyBriefClaim {
  const BriefClaimNotBusinessDay();
}

/// No se pudo consultar (sin red, sin sesión, RPC que no existe todavía).
class BriefClaimUnavailable extends DailyBriefClaim {
  const BriefClaimUnavailable();
}

/// `daily_brief_status()`: el interruptor general y las piezas.
class DailyBriefStatus {
  const DailyBriefStatus({
    required this.enabled,
    this.pieces = const {},
    this.reachable = true,
  });

  /// Apagado: la app no muestra nada nuevo.
  static const off = DailyBriefStatus(enabled: false);

  /// No se pudo preguntar (sin red, error del servidor). No es "apagado":
  /// la app no muestra nada nuevo, pero tampoco da el día por cerrado.
  static const unreachable = DailyBriefStatus(enabled: false, reachable: false);

  final bool enabled;

  /// `false` solo cuando la consulta falló; ver [unreachable].
  final bool reachable;

  /// `push`, `feed`, `topics`, `sources`, `market`, `compare`, `videos`.
  final Map<String, bool> pieces;

  /// Una pieza que falta en la respuesta vale `true` (igual que el servidor).
  bool piece(String key) => enabled && (pieces[key] ?? true);

  static DailyBriefStatus parse(Object? raw) {
    if (raw is! Map || raw['enabled'] != true) return off;
    final pieces = raw['pieces'];
    return DailyBriefStatus(
      enabled: true,
      pieces: {
        if (pieces is Map)
          for (final e in pieces.entries)
            if (e.key is String && e.value is bool)
              e.key as String: e.value as bool,
      },
    );
  }
}

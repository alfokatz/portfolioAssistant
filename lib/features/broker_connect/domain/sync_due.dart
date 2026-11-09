/// Al abrir la app o volver a ella, ¿toca sincronizar un bróker? Sí si
/// nunca se sincronizó o si lo último tiene [staleAfter] o más. Cada bróker
/// pone su [staleAfter] (según cada cuánto cambian sus datos); la regla es
/// la misma para todos.
bool isSyncDue(
  DateTime? lastSyncAt, {
  required Duration staleAfter,
  required DateTime now,
}) => lastSyncAt == null || now.difference(lastSyncAt) >= staleAfter;

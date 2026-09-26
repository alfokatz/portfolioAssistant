/// Prefijo del mensaje de usuario con snapshot fresco y surface ID del turno.
///
/// [snapshotLabel]: el pipeline por modos usa `PORTFOLIO_SNAPSHOT` (aunque
/// sus reglas de grounding digan ASSISTANT_SNAPSHOT); el unificado usa
/// `ASSISTANT_SNAPSHOT`, el mismo nombre que sus reglas.
String portfolioQaUserMessageBody({
  required String portfolioSnapshotJson,
  required String question,
  required String surfaceId,
  String snapshotLabel = 'PORTFOLIO_SNAPSHOT',
}) {
  return '''
$snapshotLabel (usar solo estos datos):
$portfolioSnapshotJson

PREGUNTA DEL USUARIO:
$question

SURFACE_ID (usar exactamente en createSurface y updateComponents):
$surfaceId
''';
}

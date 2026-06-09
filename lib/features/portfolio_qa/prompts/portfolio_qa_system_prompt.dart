/// Prefijo del mensaje de usuario con snapshot fresco y surface ID del turno.
String portfolioQaUserMessageBody({
  required String portfolioSnapshotJson,
  required String question,
  required String surfaceId,
}) {
  return '''
PORTFOLIO_SNAPSHOT (usar solo estos datos):
$portfolioSnapshotJson

PREGUNTA DEL USUARIO:
$question

SURFACE_ID (usar exactamente en createSurface y updateComponents):
$surfaceId
''';
}

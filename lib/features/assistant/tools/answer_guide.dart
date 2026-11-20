/// Instrucciones "justo a tiempo": cómo responder con los datos de una tool
/// viajan en su resultado (`answer_guide`), no en el system prompt.
///
/// Por qué: el system prompt es un prefijo fijo que se cachea y que el proxy
/// valida por hash. Si cada funcionalidad agrega ahí sus reglas de
/// respuesta, crece sin límite, cada cambio obliga a desplegar `ai-chat`
/// antes que la app y las reglas compiten entre sí. En el resultado de la
/// tool, la regla solo entra al contexto cuando se usa, y justo al lado de
/// los datos.
///
/// Qué va acá: el formato y el tono de la respuesta para ESE resultado.
/// Qué NO va: cuándo llamar a la tool (eso decide la ronda 1; va en la
/// descripción de la tool o en el intent del prompt) ni reglas generales
/// (grounding, estado locked/failed), que siguen en el prompt y ganan si hay
/// conflicto.
abstract final class AnswerGuide {
  static const key = 'answer_guide';

  /// [result] con su guía de respuesta.
  static Map<String, Object?> attach(
    Map<String, Object?> result,
    String guide,
  ) => {...result, key: guide};
}

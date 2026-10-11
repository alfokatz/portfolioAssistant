import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';

/// La memoria de Porty: lo que va aprendiendo del usuario en el chat. A
/// diferencia de las operaciones de cartera, estas tools SÍ escriben (como
/// `save_goal`): recordar es reversible y el usuario ve y borra todo en
/// Ajustes → "Lo que Porty sabe de vos". La app avisa debajo de la
/// respuesta qué anotó (ver `AssistantTurnPolicy.noticesFor`).
abstract final class MemoryTools {
  static List<DataTool> build(AssistantToolContext ctx) => [
    RememberAboutUserTool(ctx),
    ForgetAboutUserTool(ctx),
  ];

  /// Referencia corta de cada dato en `user_memory` del brief ("m1", "m2"…,
  /// en el orden de [AssistantToolContext.userMemories]): un uuid por dato
  /// gastaría tokens en cada turno. El brief y las tools del turno ven la
  /// misma lista, así que la referencia es estable dentro del turno.
  static String refOf(int index) => 'm${index + 1}';

  static UserMemory? byRef(AssistantToolContext ctx, String? ref) {
    final match = RegExp(r'^m(\d+)$').firstMatch(ref?.trim() ?? '');
    if (match == null) return null;
    final index = int.parse(match.group(1)!) - 1;
    final memories = ctx.userMemories;
    return index >= 0 && index < memories.length ? memories[index] : null;
  }
}

class RememberAboutUserTool implements DataTool {
  RememberAboutUserTool(this.ctx);

  final AssistantToolContext ctx;

  static const toolName = 'remember_about_user';

  @override
  String get name => toolName;

  @override
  String get description =>
      'Saves something DURABLE the user told you about THEMSELVES, so you '
      'know them better in future conversations: goals and things they want '
      'to buy or achieve ("quiero comprarme una MacBook Neo rosa", "quiero '
      'viajar a Japón en 2027", "me quiero jubilar a los 60"), their '
      'finances ("ahorro 200 por mes", "cobro en pesos", "tengo 1000 en el '
      'banco"), life situation ("soy estudiante", "tengo dos hijos", "tengo '
      '24 años") and investing preferences ("prefiero ETFs", "no quiero '
      'tabacaleras"). Call it in the SAME turn you answer, alongside other '
      'tools, without asking permission (the app tells the user what you '
      'noted). Write `fact` in Spanish, third person, short and specific, '
      'merging what you learned in this conversation ("Quiere comprarse una '
      'MacBook Neo rosa en unos 14 meses"). If it updates or contradicts a '
      'fact in PORTFOLIO_BRIEF user_memory, pass its id as replaces_id '
      'instead of adding a duplicate. NEVER for: one-off questions, things '
      'already in user_memory or user_profile, their portfolio positions, '
      'health, religion, politics, sexuality, or account numbers, passwords '
      'and ID documents.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'fact': {
        'type': 'string',
        'description': 'The fact, in Spanish, max 200 characters.',
      },
      'category': {
        'type': 'string',
        'enum': ['goal', 'finances', 'life', 'preference', 'other'],
      },
      'replaces_id': {
        'type': 'string',
        'description': 'id ("m3") of the user_memory fact this one updates.',
      },
    },
    'required': ['fact', 'category'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final save = ctx.saveMemory;
    if (save == null) return {'status': 'failed'};
    final fact = ToolArgs.string(args, 'fact');
    if (fact == null || fact.trim().length < 3) return ToolArgs.invalid();
    final category =
        UserMemoryCategory.fromStorage(ToolArgs.string(args, 'category')) ??
        UserMemoryCategory.other;
    final replaced = MemoryTools.byRef(
      ctx,
      ToolArgs.string(args, 'replaces_id'),
    );
    // El mismo dato dos veces (el modelo a veces repite en un seguimiento).
    final normalized = fact.trim().toLowerCase();
    if (replaced == null &&
        ctx.userMemories.any((m) => m.content.toLowerCase() == normalized)) {
      return {'status': 'ok', 'saved': false, 'reason': 'already_known'};
    }
    try {
      final memory = await save(fact, category, replacesId: replaced?.id);
      ctx.rememberedFacts.add(memory.content);
      return {'status': 'ok', 'saved': true};
    } on UserMemoryLimitReached {
      return {
        'status': 'invalid',
        'reason': 'memory_full',
        'message':
            'Porty already remembers ${UserMemory.maxPerUser} facts. Answer '
            'normally and, only if relevant, tell the user they can delete '
            'old ones in Ajustes → Lo que Porty sabe de vos.',
      };
    } on UserMemoryFailure {
      return {'status': 'failed'};
    }
  }
}

class ForgetAboutUserTool implements DataTool {
  ForgetAboutUserTool(this.ctx);

  final AssistantToolContext ctx;

  static const toolName = 'forget_about_user';

  @override
  String get name => toolName;

  @override
  String get description =>
      'Deletes a fact from PORTFOLIO_BRIEF user_memory when the user asks you '
      'to forget it ("olvidate de eso") or it is no longer true ("ya me '
      'compré la compu", "ya no quiero viajar"). Never delete on your own '
      'for any other reason.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'memory_id': {
        'type': 'string',
        'description': 'id of the fact in user_memory ("m2").',
      },
    },
    'required': ['memory_id'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final delete = ctx.deleteMemory;
    if (delete == null) return {'status': 'failed'};
    final memory = MemoryTools.byRef(ctx, ToolArgs.string(args, 'memory_id'));
    if (memory == null) {
      return {'status': 'invalid', 'reason': 'unknown_memory_id'};
    }
    try {
      await delete(memory.id);
      return {'status': 'ok', 'deleted': true};
    } catch (_) {
      return {'status': 'failed'};
    }
  }
}

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';

/// El brief de hoy para la tool `get_daily_brief` del chat: el payload de
/// §3.4 sin el número de versión (`v`) ni `audio`. `null` si todavía no hay
/// brief de hoy (el chat contesta `not_ready`).
///
/// Lee lo que la Home ya armó (el mismo que muestra la pantalla): no genera
/// nada ni llama a un modelo.
Map<String, Object?>? dailyBriefForChat(DailyBrief? brief, {DateTime? now}) {
  if (brief == null) return null;
  if (brief.day != DailyBriefNumbers.dayKey(now ?? DateTime.now())) return null;
  return {...brief.toJson()}
    ..remove('v')
    ..remove('audio');
}

/// El callback que el chat inyecta como `ctx.loadDailyBrief`
/// (`Future<Map<String, Object?>?> Function()`), como `loadWeeklyReport`.
final dailyBriefChatLoaderProvider =
    Provider<Future<Map<String, Object?>?> Function()>(
      (ref) =>
          () async =>
              dailyBriefForChat(ref.read(dailyBriefControllerProvider).brief),
    );

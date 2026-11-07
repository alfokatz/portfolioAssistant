import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/confirm_sheet.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';
import 'package:portfolio_assistant/features/porty_memory/providers/user_memory_provider.dart';
import 'package:portfolio_assistant/features/porty_memory/view/tell_porty_screen.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/features/porty_memory/providers/porty_topics_provider.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/porty_topic.dart';

/// Ajustes → "Lo que Porty sabe de vos": todo lo que Porty anotó en el
/// chat (y lo que el usuario agregó a mano), agrupado por tema. Cada dato
/// se borra solo; también se puede borrar todo o contarle algo nuevo.
class PortyMemoryScreen extends StatefulHookConsumerWidget {
  const PortyMemoryScreen({super.key});

  @override
  ConsumerState<PortyMemoryScreen> createState() => _PortyMemoryScreenState();
}

class _PortyMemoryScreenState extends BaseStatefulWidget<PortyMemoryScreen> {
  // Se empuja por encima del shell, que ya escucha las alertas globales.
  @override
  bool get subscribesToGlobalEvents => false;

  @override
  void initState() {
    super.initState();
    runAfterPostFrameCallback(() {
      ref.read(userMemoryProvider.notifier).load();
      ref.read(portyTopicsProvider.notifier).load();
    });
  }

  Future<void> _deleteTopic(PortyTopic topic) async {
    try {
      await ref.read(portyTopicsProvider.notifier).remove(topic.ticker);
    } catch (_) {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'porty_memory_error'.tr());
    }
  }

  Future<void> _delete(UserMemory memory) async {
    try {
      await ref.read(userMemoryProvider.notifier).remove(memory.id);
    } catch (_) {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'porty_memory_error'.tr());
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'porty_memory_clear_title'.tr(),
      body: 'porty_memory_clear_body'.tr(),
      confirmLabel: 'porty_memory_clear_confirm'.tr(),
    );
    if (!confirmed) return;
    try {
      await ref.read(userMemoryProvider.notifier).clear();
      await ref.read(portyTopicsProvider.notifier).clear();
    } catch (_) {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'porty_memory_error'.tr());
    }
  }

  Future<void> _tell(TellPortyPrompt prompt) async {
    if (ref.read(userMemoryProvider).memories.length >= UserMemory.maxPerUser) {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'porty_memory_full'.tr());
      return;
    }
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TellPortyScreen(prompt: prompt)),
    );
    if (added == true) {
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'porty_memory_added'.tr());
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final state = ref.watch(userMemoryProvider);
    final memories = state.memories;
    final topics = ref.watch(portyTopicsProvider).topics;

    return Scaffold(
      appBar: AppBar(),
      body:
          !state.loaded
              ? Center(child: PortyLoader(message: 'loader_one_moment'.tr()))
              : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.pageHorizontal,
                  0,
                  AppDimens.pageHorizontal,
                  AppDimens.sp32,
                ),
                children: [
                  Row(
                    children: [
                      const ExcludeSemantics(
                        child: PortyAvatar(size: 56, animated: true),
                      ),
                      const SizedBox(width: AppDimens.sp12),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            'porty_memory_title'.tr(),
                            style: tt.displaySmall?.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              height: 1.2,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.sp12),
                  Text(
                    memories.isEmpty
                        ? 'porty_memory_empty'.tr()
                        : 'porty_memory_body'.tr(),
                    style: tt.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp20),
                  // Sin nada anotado, las preguntas de Porty son lo primero.
                  if (memories.isEmpty) ...[
                    TellPortyPromptCards(onSelected: _tell),
                    const SizedBox(height: AppDimens.sp24),
                  ],
                  for (final category in UserMemoryCategory.values)
                    if (memories.any((m) => m.category == category)) ...[
                      _CategoryCard(
                        category: category,
                        memories: [
                          for (final m in memories)
                            if (m.category == category) m,
                        ],
                        onDelete: _delete,
                      ),
                      const SizedBox(height: AppDimens.sp16),
                    ],
                  if (topics.isNotEmpty) ...[
                    _TopicsCard(topics: topics, onDelete: _deleteTopic),
                    const SizedBox(height: AppDimens.sp16),
                  ],
                  if (memories.isNotEmpty) ...[
                    const SizedBox(height: AppDimens.sp8),
                    _SectionLabel('tell_porty_more'.tr()),
                    TellPortyPromptCards(onSelected: _tell),
                    const SizedBox(height: AppDimens.sp8),
                  ],
                  if (memories.isNotEmpty || topics.isNotEmpty)
                    Center(
                      child: TextButton(
                        onPressed: _clearAll,
                        child: Text(
                          'porty_memory_clear'.tr(),
                          style: tt.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.memories,
    required this.onDelete,
  });

  final UserMemoryCategory category;
  final List<UserMemory> memories;
  final ValueChanged<UserMemory> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppDimens.sp4,
            bottom: AppDimens.sp8,
          ),
          child: Text(
            'porty_memory_category_${category.storageValue}'.tr().toUpperCase(),
            style: tt.labelSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              for (final (i, memory) in memories.indexed) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppDimens.cardPadding,
                    endIndent: AppDimens.cardPadding,
                    color: colors.border,
                  ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppDimens.cardPadding,
                    top: AppDimens.sp4,
                    bottom: AppDimens.sp4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          memory.content,
                          style: tt.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'porty_memory_delete'.tr(),
                        onPressed: () => onDelete(memory),
                        icon: Icon(
                          Icons.close_rounded,
                          size: AppDimens.iconMd,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// De qué acciones le habló a Porty (`porty_topics`): lo arma la app con
/// cada charla. Se ven los más recientes y se borran de a uno.
class _TopicsCard extends StatelessWidget {
  const _TopicsCard({required this.topics, required this.onDelete});

  final List<PortyTopic> topics;
  final ValueChanged<PortyTopic> onDelete;

  /// Cuántos se muestran: el resto sigue guardado (hasta 50).
  static const visible = 10;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final shown = topics.take(visible).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('porty_memory_topics'.tr()),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              for (final (i, topic) in shown.indexed) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppDimens.cardPadding,
                    endIndent: AppDimens.cardPadding,
                    color: colors.border,
                  ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppDimens.cardPadding,
                    top: AppDimens.sp8,
                    bottom: AppDimens.sp8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${topic.ticker} · ${DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag()).format(topic.lastAskedAt.toLocal())}',
                              style: tt.bodyMedium?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              topic.question,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'porty_memory_delete'.tr(),
                        onPressed: () => onDelete(topic),
                        icon: Icon(
                          Icons.close_rounded,
                          size: AppDimens.iconMd,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: AppDimens.sp4, bottom: AppDimens.sp8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.customColors.textSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    ),
  );
}

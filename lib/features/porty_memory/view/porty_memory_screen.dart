import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';
import 'package:portfolio_assistant/features/porty_memory/providers/user_memory_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';

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
    runAfterPostFrameCallback(
      () => ref.read(userMemoryProvider.notifier).load(),
    );
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('porty_memory_clear_title'.tr()),
            content: Text('porty_memory_clear_body'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('porty_memory_cancel'.tr()),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('porty_memory_clear_confirm'.tr()),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(userMemoryProvider.notifier).clear();
    } catch (_) {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'porty_memory_error'.tr());
    }
  }

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddMemorySheet(),
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
                  PositionPrimaryButton(
                    label: 'porty_memory_add'.tr(),
                    onPressed:
                        memories.length >= UserMemory.maxPerUser ? null : _add,
                  ),
                  if (memories.isNotEmpty) ...[
                    const SizedBox(height: AppDimens.sp8),
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

/// "Contale algo a Porty": un texto corto y de qué se trata.
class _AddMemorySheet extends ConsumerStatefulWidget {
  const _AddMemorySheet();

  @override
  ConsumerState<_AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends ConsumerState<_AddMemorySheet> {
  final _controller = TextEditingController();
  var _category = UserMemoryCategory.goal;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(userMemoryProvider.notifier)
          .add(_controller.text, category: _category);
      if (mounted) Navigator.of(context).pop(true);
    } on UserMemoryLimitReached {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'porty_memory_full'.tr());
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'porty_memory_error'.tr());
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        MediaQuery.viewInsetsOf(context).bottom + AppDimens.sp24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'porty_memory_add_title'.tr(),
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.sp12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: UserMemory.maxLength,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'porty_memory_add_hint'.tr(),
            ),
          ),
          const SizedBox(height: AppDimens.sp8),
          Wrap(
            spacing: AppDimens.sp8,
            runSpacing: AppDimens.sp8,
            children: [
              for (final category in UserMemoryCategory.values)
                ChoiceChip(
                  label: Text(
                    'porty_memory_category_${category.storageValue}'.tr(),
                  ),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.sp20),
          PositionPrimaryButton(
            label: 'porty_memory_save'.tr(),
            loading: _saving,
            onPressed:
                _saving || _controller.text.trim().length < 3 ? null : _save,
          ),
        ],
      ),
    );
  }
}

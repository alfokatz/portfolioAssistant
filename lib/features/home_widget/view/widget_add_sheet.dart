import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_prompt_provider.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Desde dónde se abrió la hoja (prop `source` de los eventos).
enum WidgetPromptSource { auto, settings }

class _Session {
  /// Tocó "Agregar" (o entró directo a los pasos): cerrar ya no es
  /// "Ahora no".
  bool engaged = false;
}

/// "Tené a Porty en tu pantalla de inicio": vista previa del widget mediano
/// con los datos reales, "Agregar" y "Ahora no". En Android pide al launcher
/// que lo agregue; si no puede (y en iOS, que no tiene API) muestra los pasos
/// a mano en la misma hoja. Con un widget ya instalado abre directo en los
/// pasos, para sumar otro tamaño.
class WidgetAddSheet extends ConsumerStatefulWidget {
  const WidgetAddSheet({
    super.key,
    required this.source,
    this.startOnSteps = false,
  }) : _session = null;

  const WidgetAddSheet._(this.source, this.startOnSteps, this._session);

  final WidgetPromptSource source;
  final bool startOnSteps;
  final _Session? _session;

  /// Abre la hoja y registra `widget_prompt_shown` / `_dismissed`.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required WidgetPromptSource source,
    bool installed = false,
  }) async {
    final events = ref.read(productEventsProvider);
    final session = _Session()..engaged = installed;
    events.log(ProductEvent.widgetPromptShown, {'source': source.name});
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WidgetAddSheet._(source, installed, session),
    );
    if (!session.engaged) {
      events.log(ProductEvent.widgetPromptDismissed, {'source': source.name});
    }
  }

  @override
  ConsumerState<WidgetAddSheet> createState() => _WidgetAddSheetState();
}

class _WidgetAddSheetState extends ConsumerState<WidgetAddSheet> {
  late bool _steps = widget.startOnSteps;

  /// El launcher de Android no deja pedir el alta: se explica el porqué.
  bool _manualFallback = false;
  bool _busy = false;

  _Session get _session => widget._session ?? _Session();

  Future<void> _onAdd() async {
    if (_busy) return;
    PortyHapticsService.maybeOf(context)?.selectionTap();
    final store = ref.read(homeWidgetStoreProvider);
    final events = ref.read(productEventsProvider);
    _session.engaged = true;
    setState(() => _busy = true);
    var pinned = false;
    if (store.platform == 'android') {
      try {
        if (await store.isPinSupported()) {
          await store.requestPin();
          pinned = true;
        }
      } catch (_) {}
    }
    events.log(ProductEvent.widgetPromptAddTapped, {
      'platform': store.platform,
      'method': pinned ? 'pin' : 'steps',
    });
    if (!mounted) return;
    if (pinned) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _steps = true;
      _manualFallback = store.platform == 'android';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final android = ref.watch(homeWidgetStoreProvider).platform == 'android';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_steps) ...[
              const _WidgetPreview(),
              const SizedBox(height: AppDimens.sp20),
            ],
            Semantics(
              header: true,
              child: Text(
                !_steps
                    ? 'home_widget_add_title'.tr()
                    : widget.startOnSteps
                    ? 'home_widget_add_steps_more_title'.tr()
                    : 'home_widget_add_steps_title'.tr(),
                textAlign: TextAlign.center,
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            if (!_steps)
              Text(
                'home_widget_add_body'.tr(),
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              )
            else ...[
              if (_manualFallback)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppDimens.sp8),
                  child: Text(
                    'home_widget_add_manual_note'.tr(),
                    textAlign: TextAlign.center,
                    style: tt.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              const SizedBox(height: AppDimens.sp8),
              for (final (i, step)
                  in (android ? _androidSteps : _iosSteps).indexed)
                _StepRow(number: i + 1, icon: step.$1, text: step.$2.tr()),
            ],
            const SizedBox(height: AppDimens.sp24),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed:
                    _steps
                        ? () => Navigator.of(context).pop()
                        : (_busy ? null : _onAdd),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.textPrimary,
                  foregroundColor: colors.surfaceCard,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  ),
                ),
                child: Text(
                  _steps
                      ? 'home_widget_add_done'.tr()
                      : 'home_widget_add_confirm'.tr(),
                  style: tt.titleSmall?.copyWith(
                    color: colors.surfaceCard,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (!_steps) ...[
              const SizedBox(height: AppDimens.sp4),
              SizedBox(
                height: AppDimens.touchTarget,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                    ),
                  ),
                  child: Text(
                    'home_widget_add_later'.tr(),
                    style: tt.titleSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ] else
              const SizedBox(height: AppDimens.sp8),
          ],
        ),
      ),
    );
  }
}

const _iosSteps = <(IconData, String)>[
  (Icons.touch_app_outlined, 'home_widget_add_steps_ios_1'),
  (Icons.add_circle_outline_rounded, 'home_widget_add_steps_ios_2'),
  (Icons.search_rounded, 'home_widget_add_steps_ios_3'),
  (Icons.aspect_ratio_rounded, 'home_widget_add_steps_ios_4'),
  (Icons.check_circle_outline_rounded, 'home_widget_add_steps_ios_5'),
];

const _androidSteps = <(IconData, String)>[
  (Icons.touch_app_outlined, 'home_widget_add_steps_android_1'),
  (Icons.widgets_outlined, 'home_widget_add_steps_android_2'),
  (Icons.search_rounded, 'home_widget_add_steps_android_3'),
  (Icons.open_with_rounded, 'home_widget_add_steps_android_4'),
];

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.icon,
    required this.text,
  });

  final int number;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp8),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$number',
              style: tt.titleSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.inset,
              borderRadius: BorderRadius.circular(AppDimens.radiusMd),
            ),
            child: Icon(
              icon,
              size: AppDimens.iconMd,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            child: Text(
              text,
              style: tt.bodyMedium?.copyWith(
                color: colors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El widget mediano dibujado en Flutter con lo que dice el snapshot de hoy;
/// sin datos, una versión ilustrativa sin números.
class _WidgetPreview extends ConsumerWidget {
  const _WidgetPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final data = ref.watch(widgetPreviewProvider).valueOrNull;
    final tabular = const [FontFeature.tabularFigures()];
    final changeColor = switch (data?.direction) {
      'up' => colors.profit,
      'down' => colors.loss,
      _ => colors.textSecondary,
    };
    final changeLine = data?.changePct ?? '';

    return Semantics(
      label: 'home_widget_add_preview_a11y'.tr(),
      container: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppDimens.cardPadding),
          decoration: BoxDecoration(
            color: colors.inset,
            borderRadius: BorderRadius.circular(AppDimens.radiusXl),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'home_widget_add_preview_name'.tr(),
                      style: tt.labelLarge?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (data?.period != null)
                    Text(
                      data!.period!,
                      style: tt.labelMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.sp8),
              Text(
                data?.title ?? 'home_widget_your_portfolio'.tr(),
                style: tt.headlineSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
              if (changeLine.isNotEmpty) ...[
                const SizedBox(height: AppDimens.sp2),
                Text(
                  changeLine,
                  style: tt.bodyMedium?.copyWith(
                    color: changeColor,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.sp8),
              Text(
                data?.phrase ?? 'home_widget_add_preview_sample'.tr(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

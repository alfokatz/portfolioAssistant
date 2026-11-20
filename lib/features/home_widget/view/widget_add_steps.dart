import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Qué dibuja cada paso: una pantalla de inicio esquemática con el lugar
/// donde tocar marcado en terracota.
enum WidgetAddShot { holdEmpty, editMenu, widgetsMenu, search, sizes, add, drag }

typedef WidgetAddStep = ({WidgetAddShot shot, String textKey});

const widgetAddStepsIos = <WidgetAddStep>[
  (shot: WidgetAddShot.holdEmpty, textKey: 'home_widget_add_steps_ios_1'),
  (shot: WidgetAddShot.editMenu, textKey: 'home_widget_add_steps_ios_2'),
  (shot: WidgetAddShot.search, textKey: 'home_widget_add_steps_ios_3'),
  (shot: WidgetAddShot.sizes, textKey: 'home_widget_add_steps_ios_4'),
  (shot: WidgetAddShot.add, textKey: 'home_widget_add_steps_ios_5'),
];

const widgetAddStepsAndroid = <WidgetAddStep>[
  (shot: WidgetAddShot.holdEmpty, textKey: 'home_widget_add_steps_android_1'),
  (shot: WidgetAddShot.widgetsMenu, textKey: 'home_widget_add_steps_android_2'),
  (shot: WidgetAddShot.search, textKey: 'home_widget_add_steps_android_3'),
  (shot: WidgetAddShot.drag, textKey: 'home_widget_add_steps_android_4'),
];

/// Los pasos para agregar el widget a mano, de a uno: la ilustración, la
/// instrucción, el progreso y "Siguiente" / "Entendido". Se puede deslizar.
class WidgetAddSteps extends StatefulWidget {
  const WidgetAddSteps({super.key, required this.steps, required this.onDone});

  final List<WidgetAddStep> steps;
  final VoidCallback onDone;

  @override
  State<WidgetAddSteps> createState() => _WidgetAddStepsState();
}

class _WidgetAddStepsState extends State<WidgetAddSteps> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _last => _index == widget.steps.length - 1;

  void _next() {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    if (_last) {
      widget.onDone();
      return;
    }
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _pages.jumpToPage(_index + 1);
    } else {
      _pages.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final total = widget.steps.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 320,
          child: PageView.builder(
            controller: _pages,
            itemCount: total,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final step = widget.steps[i];
              return Column(
                children: [
                  // La ilustración cede lugar si el texto crece (letra grande).
                  Expanded(
                    child: ExcludeSemantics(child: _ShotFrame(shot: step.shot)),
                  ),
                  const SizedBox(height: AppDimens.sp16),
                  Text(
                    'home_widget_add_step_of'.tr(
                      namedArgs: {'current': '${i + 1}', 'total': '$total'},
                    ),
                    style: tt.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp4),
                  Text(
                    step.textKey.tr(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: tt.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppDimens.sp12),
        _Dots(count: total, index: _index),
        const SizedBox(height: AppDimens.sp20),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _next,
            style: FilledButton.styleFrom(
              backgroundColor: colors.textPrimary,
              foregroundColor: colors.surfaceCard,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              ),
            ),
            child: Text(
              (_last ? 'home_widget_add_done' : 'home_widget_add_next').tr(),
              style: tt.titleSmall?.copyWith(
                color: colors.surfaceCard,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration:
                  reduce ? Duration.zero : const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? colors.accentBlue : colors.track,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

/// La "pantalla" de cada paso: fondo `inset`, borde fino, esquinas de sheet.
class _ShotFrame extends StatelessWidget {
  const _ShotFrame({required this.shot});

  final WidgetAddShot shot;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimens.sp16),
      decoration: BoxDecoration(
        color: colors.inset,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(color: colors.border),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: switch (shot) {
          WidgetAddShot.holdEmpty => const _HoldEmpty(),
          WidgetAddShot.editMenu => const _Menu(
            pill: 'home_widget_shot_edit',
            items: [
              ('home_widget_shot_add_widget', Icons.add_rounded),
              ('home_widget_shot_customize', Icons.tune_rounded),
            ],
          ),
          WidgetAddShot.widgetsMenu => const _Menu(
            items: [
              ('home_widget_shot_wallpaper', Icons.wallpaper_rounded),
              ('home_widget_shot_widgets', Icons.widgets_outlined),
              ('home_widget_shot_settings', Icons.settings_outlined),
            ],
            highlight: 1,
          ),
          WidgetAddShot.search => const _Search(),
          WidgetAddShot.sizes => const _Sizes(),
          WidgetAddShot.add => const _Add(),
          WidgetAddShot.drag => const _Drag(),
        },
      ),
    );
  }
}

/// Marca terracota alrededor de lo que hay que tocar.
class _Ring extends StatelessWidget {
  const _Ring({required this.child, this.radius = AppDimens.radiusMd});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 3),
        border: Border.all(color: colors.accentBlue, width: 2),
      ),
      child: child,
    );
  }
}

/// El dedo: un círculo terracota translúcido.
class _Touch extends StatelessWidget {
  const _Touch({this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.accentBlue.withValues(alpha: 0.22),
        border: Border.all(color: colors.accentBlue, width: 2),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: context.customColors.track,
      borderRadius: BorderRadius.circular(9),
    ),
  );
}

class _HoldEmpty extends StatelessWidget {
  const _HoldEmpty();

  @override
  Widget build(BuildContext context) {
    Widget row(List<bool> icons) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, icon) in icons.indexed) ...[
          if (i > 0) const SizedBox(width: 18),
          icon ? const _AppIcon() : const SizedBox(width: 34, height: 34),
        ],
      ],
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row([true, true, true, true]),
            const SizedBox(height: 16),
            row([true, true, true, true]),
            const SizedBox(height: 16),
            row([true, false, false, false]),
          ],
        ),
        // El espacio vacío de la última fila.
        const Positioned(bottom: 6, right: 52, child: _Touch(size: 40)),
      ],
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({this.pill, required this.items, this.highlight = 0});

  /// El botón de arriba ("Editar") que abre el menú (solo iOS).
  final String? pill;
  final List<(String, IconData)> items;
  final int highlight;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pill != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              pill!.tr(),
              style: tt.labelMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp8),
        ],
        Container(
          width: 210,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, (key, icon)) in items.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: _MenuRow(
                    text: key.tr(),
                    icon: icon,
                    selected: i == highlight,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.text,
    required this.icon,
    required this.selected,
  });

  final String text;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: tt.bodySmall?.copyWith(
                color: selected ? colors.textPrimary : colors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Icon(
            icon,
            size: AppDimens.iconSm,
            color: selected ? colors.textPrimary : colors.textSecondary,
          ),
        ],
      ),
    );
    return selected ? _Ring(radius: 8, child: row) : row;
  }
}

class _Search extends StatelessWidget {
  const _Search();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: 230,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: AppDimens.iconSm,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Porty',
                  style: tt.bodySmall?.copyWith(color: colors.textPrimary),
                ),
                Container(
                  width: 1.5,
                  height: 14,
                  margin: const EdgeInsets.only(left: 1),
                  color: colors.accentBlue,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.sp12),
          _Ring(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  const PortyAvatar(size: 28),
                  const SizedBox(width: AppDimens.sp8),
                  Text(
                    'Porty',
                    style: tt.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El widget en miniatura: la cara y el % del día, sin montos.
class _MiniWidget extends StatelessWidget {
  const _MiniWidget({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PortyAvatar(size: height > 60 ? 20 : 14),
          const Spacer(),
          Text(
            '+1,2%',
            maxLines: 1,
            style: (height > 60 ? tt.titleSmall : tt.labelSmall)?.copyWith(
              color: colors.profit,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sizes extends StatelessWidget {
  const _Sizes();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const _MiniWidget(width: 58, height: 58),
            const SizedBox(width: 14),
            const _Ring(
              radius: 12,
              child: _MiniWidget(width: 112, height: 58),
            ),
            const SizedBox(width: 14),
            const _MiniWidget(width: 74, height: 80),
          ],
        ),
        const SizedBox(height: AppDimens.sp12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == 1 ? colors.textPrimary : colors.track,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Add extends StatelessWidget {
  const _Add();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _MiniWidget(width: 140, height: 70),
        const SizedBox(height: AppDimens.sp16),
        _Ring(
          radius: AppDimens.radiusPill,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: colors.textPrimary,
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: AppDimens.iconSm,
                  color: colors.surfaceCard,
                ),
                const SizedBox(width: 4),
                Text(
                  'home_widget_shot_add_widget'.tr(),
                  style: tt.labelLarge?.copyWith(
                    color: colors.surfaceCard,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Drag extends StatelessWidget {
  const _Drag();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AppIcon(),
            SizedBox(height: 16),
            _AppIcon(),
            SizedBox(height: 16),
            _AppIcon(),
          ],
        ),
        const SizedBox(width: 22),
        Stack(
          clipBehavior: Clip.none,
          children: [
            const _Ring(
              radius: 12,
              child: _MiniWidget(width: 130, height: 70),
            ),
            Positioned(
              right: -12,
              bottom: -12,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentBlue,
                ),
                child: Icon(
                  Icons.open_with_rounded,
                  size: AppDimens.iconSm,
                  color: colors.onAccent,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

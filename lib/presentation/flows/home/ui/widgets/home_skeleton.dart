import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_section_tabs.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_hero_section.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/positions_section.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';

/// La Home mientras carga sin nada guardado: la misma estructura que con
/// datos (card del total con gráfico y selector de rango, selector
/// Activos/Insights, filas de posiciones), armada con los mismos widgets en
/// modo skeleton, así el cambio a datos no mueve nada. Un solo pulso lento
/// para todo; estático con reduce motion.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  /// Filas de posiciones del skeleton (las que entran sin "Ver todas").
  static const rows = 5;

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PortfolioHeroSection.skeleton(),
            const SizedBox(height: AppDimens.sectionGap),
            HomeSectionTabs(selected: HomeSection.assets, onSelected: (_) {}),
            const SizedBox(height: AppDimens.sp16),
            const PositionsSection.skeleton(rows: rows),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_plan_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_skeleton.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/shared/utils/provider_lookup.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';

/// Resuelve el [CompanyBrand] de un ticker vía [CompanyBrandLoader] y
/// reconstruye cuando llega. Sin `ProviderScope` (tests aislados) queda en
/// el brand vacío, sin requests.
class QaBrandBuilder extends StatefulWidget {
  const QaBrandBuilder({
    super.key,
    required this.ticker,
    required this.builder,
  });

  final String ticker;
  final Widget Function(BuildContext context, CompanyBrand brand) builder;

  @override
  State<QaBrandBuilder> createState() => _QaBrandBuilderState();
}

class _QaBrandBuilderState extends State<QaBrandBuilder> {
  late CompanyBrand _brand = CompanyBrand(ticker: widget.ticker);
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested || widget.ticker.isEmpty) return;
    _requested = true;
    final loader = readProviderOrNull(context, companyBrandLoaderProvider);
    if (loader == null) return;
    final cached = loader.peek(widget.ticker);
    if (cached != null) {
      _brand = cached;
      return;
    }
    loader.load(widget.ticker).then((brand) {
      if (mounted) setState(() => _brand = brand);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _brand);
}

/// Avatar circular del ticker: logo de la compañía si Finnhub lo tiene,
/// si no un monograma sobre un tono cálido determinístico por ticker (el
/// mismo ticker siempre sale del mismo color en toda la app).
class QaTickerAvatar extends StatelessWidget {
  const QaTickerAvatar({
    super.key,
    required this.ticker,
    this.size = 36,
    this.brand,
  });

  final String ticker;
  final double size;

  /// Si ya se resolvió afuera (p. ej. en [QaCardHeader]); si no, se resuelve acá.
  final CompanyBrand? brand;

  static const _tonesLight = [
    Color(0xFFF3E4D9), // terracota claro
    Color(0xFFE6ECE4), // salvia claro
    Color(0xFFE9E4DA), // arena
    Color(0xFFE2E8EF), // azul polvo claro
    Color(0xFFECE6EA), // malva claro
  ];

  // Mismos tonos, apagados: sobre la card oscura los pasteles claros se
  // veían como manchas de luz.
  static const _tonesDark = [
    Color(0xFF3A2C23),
    Color(0xFF2A322B),
    Color(0xFF34302A),
    Color(0xFF283038),
    Color(0xFF342D32),
  ];

  @override
  Widget build(BuildContext context) {
    final b = brand;
    if (b != null) return _avatar(b);
    return QaBrandBuilder(ticker: ticker, builder: (_, b) => _avatar(b));
  }

  Widget _avatar(CompanyBrand brand) {
    final monogram = _Monogram(ticker: ticker, size: size, tone: _tone());
    final logo = brand.logoUrl;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: QaColors.border),
        ),
        child: ClipOval(
          child:
              logo == null
                  ? monogram
                  : ColoredBox(
                    color: QaColors.surfaceCard,
                    child: Image.network(
                      logo,
                      fit: BoxFit.contain,
                      width: size,
                      height: size,
                      errorBuilder: (_, _, _) => monogram,
                      frameBuilder:
                          (context, child, frame, sync) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: frame == null && !sync ? monogram : child,
                          ),
                    ),
                  ),
        ),
      ),
    );
  }

  Color _tone() {
    var hash = 0;
    for (final unit in ticker.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final tones = QaColors.isDark ? _tonesDark : _tonesLight;
    return tones[hash % tones.length];
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({
    required this.ticker,
    required this.size,
    required this.tone,
  });

  final String ticker;
  final double size;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final letters =
        ticker.isEmpty ? '?' : ticker.substring(0, ticker.length >= 2 ? 2 : 1);
    return Container(
      color: tone,
      alignment: Alignment.center,
      child: Text(
        letters,
        style: TextStyle(
          color: QaColors.textPrimary.withValues(alpha: 0.8),
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

/// Encabezado estándar de card con identidad de ticker: avatar + ticker +
/// nombre de la compañía (resuelto del lado del cliente) + trailing.
///
/// Si hay [QaFollowUpScope], tocar el encabezado pregunta por el ticker
/// ([tapQuestion], default "¿Cómo viene X?") — el gesto natural de "quiero
/// saber más de esto".
class QaTickerHeader extends StatelessWidget {
  const QaTickerHeader({
    super.key,
    required this.ticker,
    this.subtitle,
    this.trailing,
    this.tapQuestion,
    this.avatarSize = 36,
  });

  final String ticker;

  /// Reemplaza el nombre de la compañía como subtítulo.
  final String? subtitle;
  final Widget? trailing;
  final String? tapQuestion;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    return QaBrandBuilder(
      ticker: ticker,
      builder: (context, brand) {
        final sub = subtitle ?? brand.name;
        final row = Row(
          children: [
            QaTickerAvatar(ticker: ticker, brand: brand, size: avatarSize),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ticker, style: QaText.title),
                  if (sub != null && sub.isNotEmpty)
                    Text(
                      sub,
                      style: QaText.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        );
        return QaTappable(
          question: tapQuestion ?? '¿Cómo viene $ticker?',
          child: row,
        );
      },
    );
  }
}

/// Encabezado de card sin ticker: ícono en un círculo teñido + título +
/// subtítulo opcional + trailing ("Tu portfolio", "Meta: Casa").
class QaCardTitle extends StatelessWidget {
  const QaCardTitle({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.iconColor,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? QaColors.accentBlue;
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: QaText.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  style: QaText.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// Envuelve algo tocable que dispara un follow-up: feedback de presión
/// (leve escala + opacidad) y nada más — sin ripple de Material, que se ve
/// fuera de lugar en superficies editoriales. Sin scope, es inerte.
class QaTappable extends StatefulWidget {
  const QaTappable({super.key, required this.child, this.question, this.onTap});

  final Widget child;

  /// Pregunta a enviar vía [QaFollowUpScope].
  final String? question;

  /// Acción local alternativa (abrir un link, expandir) — tiene prioridad.
  final VoidCallback? onTap;

  @override
  State<QaTappable> createState() => _QaTappableState();
}

class _QaTappableState extends State<QaTappable> {
  bool _pressed = false;

  VoidCallback? _action(BuildContext context) {
    if (widget.onTap != null) return widget.onTap;
    final q = widget.question;
    final send = QaFollowUpScope.maybeOf(context);
    if (q == null || send == null) return null;
    return () => send(q);
  }

  @override
  Widget build(BuildContext context) {
    final action = _action(context);
    if (action == null) return widget.child;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: action,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _pressed ? 0.6 : 1,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: _pressed ? 0.985 : 1,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Una acción de seguimiento sugerida al pie de una card.
class QaFollowUp {
  const QaFollowUp(
    this.label,
    this.question, {
    this.icon,
    this.feature,
    this.ticker,
  });

  /// Texto corto del chip ("Noticias").
  final String label;

  /// Pregunta completa que se envía ("¿Qué noticias hay de NVDA?").
  final String question;
  final IconData? icon;

  /// Qué feature del plan necesita la respuesta (null = ninguna especial).
  /// Sin ella, el chip se ve con candado y abre el paywall en vez de
  /// preguntar — ver [QaFollowUpBar].
  final PlanFeature? feature;

  /// Ticker del chip, para el análisis de cortesía de la semana.
  final String? ticker;
}

/// Fila de chips de seguimiento al pie de una card. Scroll horizontal si no
/// entran. Sin [QaFollowUpScope] no se muestra (no hay a dónde enviarlas).
///
/// Con [QaPlanScope]: los chips cuya feature no incluye el plan se muestran
/// con candado (a lo sumo UNO por card, y ninguno si la card ya tiene su
/// bloque bloqueado: [allowLockedChip]) y abren el paywall. El chip de
/// "Análisis" con el análisis de cortesía disponible pregunta normal y lleva
/// arriba el texto "1 análisis Gold gratis esta semana", que al gastarse se
/// va con la transición de estado del kit (el espacio se cierra, no salta).
class QaFollowUpBar extends StatelessWidget {
  const QaFollowUpBar({
    super.key,
    required this.items,
    this.limit,
    this.allowLockedChip = true,
    this.surfaceId,
  });

  final List<QaFollowUp> items;

  /// Cuántos chips mostrar como máximo, DESPUÉS de filtrar por plan.
  final int? limit;
  final bool allowLockedChip;

  /// Surface de la card, para desbloquearla en el lugar tras comprar.
  final String? surfaceId;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty || QaFollowUpScope.maybeOf(context) == null) {
      return const SizedBox.shrink();
    }
    final plan = QaPlanScope.maybeOf(context);
    final chips = <({QaFollowUp item, bool locked})>[];
    var lockedShown = false;
    var courtesy = false;
    for (final item in items) {
      final feature = item.feature;
      final allowed = plan == null || feature == null || plan.allows(feature);
      final free =
          !allowed &&
          feature == PlanFeature.companyAnalysis &&
          item.ticker != null &&
          plan.freeAnalysisCovers(item.ticker!);
      if (allowed || free) {
        chips.add((item: item, locked: false));
        if (free) courtesy = true;
      } else if (allowLockedChip && !lockedShown) {
        chips.add((item: item, locked: true));
        lockedShown = true;
      }
    }
    final visible = limit == null ? chips : chips.take(limit!).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final showCourtesy =
        courtesy &&
        visible.any(
          (c) => !c.locked && c.item.feature == PlanFeature.companyAnalysis,
        );

    return Padding(
      padding: const EdgeInsets.only(top: QaSpace.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          QaStateSwitcher(
            child:
                showCourtesy
                    ? Padding(
                      key: const ValueKey('courtesy'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 13,
                            color: QaColors.accentBlue,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '1 análisis Gold gratis esta semana',
                              style: QaText.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                    : const SizedBox(
                      key: ValueKey('none'),
                      width: double.infinity,
                    ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  visible[i].locked
                      ? _LockedChip(item: visible[i].item, surfaceId: surfaceId)
                      : QaTappable(
                        question: visible[i].item.question,
                        child: _ChipBody(item: visible[i].item),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipBody extends StatelessWidget {
  const _ChipBody({required this.item, this.locked = false});

  final QaFollowUp item;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: QaColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: QaColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locked
                ? Icons.lock_outline_rounded
                : item.icon ?? Icons.north_east_rounded,
            size: 13,
            color: locked ? QaColors.textSecondary : QaColors.accentBlue,
          ),
          const SizedBox(width: 6),
          Text(
            item.label,
            style: QaText.caption.copyWith(
              color: locked ? QaColors.textSecondary : QaColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (locked) ...[
            const SizedBox(width: 6),
            Text(
              'Gold',
              style: QaText.caption.copyWith(
                color: QaColors.accentBlue,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Chip de una feature que el plan no incluye: se ve (con candado + "Gold")
/// y abre el paywall con su `source`, sin gastar una consulta en preguntar
/// algo que Porty no podría responder.
class _LockedChip extends StatefulWidget {
  const _LockedChip({required this.item, this.surfaceId});

  final QaFollowUp item;
  final String? surfaceId;

  @override
  State<_LockedChip> createState() => _LockedChipState();
}

class _LockedChipState extends State<_LockedChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final plan = QaPlanScope.maybeOf(context);
    final feature = widget.item.feature;
    final source = 'chip_${feature?.name ?? 'gold'}';
    // Toque mínimo de 44 px aunque el chip se vea más bajo.
    return Semantics(
      button: true,
      label: 'Desbloquear con Gold: ${widget.item.label}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          setState(() => _pressed = true);
          PortyHapticsService.maybeOf(context)?.lockedTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap:
            () => plan?.openPaywall(
              QaPaywallRequest(
                source: source,
                ticker: widget.item.ticker,
                surfaceId: widget.surfaceId,
              ),
            ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: AnimatedOpacity(
              duration:
                  MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
              opacity: _pressed ? 0.6 : 1,
              child: _ChipBody(item: widget.item, locked: true),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cambio de estado del kit sin saltos: el espacio se ajusta animado y el
/// contenido hace crossfade ([QaStateMotion]). Con reduce motion, directo.
class QaStateSwitcher extends StatelessWidget {
  const QaStateSwitcher({super.key, required this.child});

  /// Con key propia por estado (así el switcher sabe que cambió).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : QaStateMotion.change;
    // Ancho completo fijo: solo anima el ALTO (lo de abajo se desliza); si
    // también animara el ancho, el contenido quedaría angosto a mitad de
    // camino y desbordaría. MotionAwareSize y no AnimatedSize directo: con
    // reduce motion la duración es cero, y un AnimatedSize de duración cero
    // se re-ensucia en su propio layout (assert de Flutter al cambiar de
    // estado, ej. el análisis de una empresa al llegar los datos).
    return SizedBox(
      width: double.infinity,
      child: MotionAwareSize(
        duration: QaStateMotion.change,
        curve: QaStateMotion.curve,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: duration,
          // Lo que se va se apaga en la mitad del tiempo: a mitad de camino
          // ya casi no se ve, y el viejo y el nuevo no se leen encimados.
          reverseDuration: duration ~/ 2,
          switchInCurve: QaStateMotion.curve,
          switchOutCurve: QaStateMotion.curve,
          layoutBuilder:
              (current, previous) => Stack(
                alignment: Alignment.topLeft,
                children: [...previous, if (current != null) current],
              ),
          child: child,
        ),
      ),
    );
  }
}

/// Follow-ups estándar por ticker, para que todas las cards de mercado
/// ofrezcan el mismo menú y en el mismo orden. [exclude] saca el que
/// corresponde a la card actual (la card de noticias no sugiere noticias).
abstract final class QaTickerFollowUps {
  static const chart = 'chart';
  static const news = 'news';
  static const earnings = 'earnings';
  static const fundamentals = 'fundamentals';
  static const compare = 'compare';
  static const analysis = 'analysis';

  /// El pedido de análisis completo de una empresa (ver `QaCompanyAnalysis`).
  /// Suelto para las cards que arman su propio menú (opciones de inversión).
  static QaFollowUp analysisFor(String ticker) => QaFollowUp(
    'Análisis',
    'Haceme un análisis de $ticker',
    icon: Icons.insights_rounded,
    feature: PlanFeature.companyAnalysis,
    ticker: ticker,
  );

  /// Primero va "Análisis": es el siguiente paso más completo desde
  /// cualquier card de un ticker, y las cards muestran solo los 3 primeros.
  static List<QaFollowUp> of(String ticker, {Set<String> exclude = const {}}) =>
      [
        if (!exclude.contains(analysis)) analysisFor(ticker),
        if (!exclude.contains(chart))
          QaFollowUp(
            'Gráfico',
            '¿Cómo viene $ticker?',
            icon: Icons.show_chart_rounded,
          ),
        if (!exclude.contains(news))
          QaFollowUp(
            'Noticias',
            '¿Qué noticias hay de $ticker?',
            icon: Icons.article_outlined,
            feature: PlanFeature.news,
            ticker: ticker,
          ),
        if (!exclude.contains(earnings))
          QaFollowUp(
            'Earnings',
            '¿Cuándo reporta $ticker y cómo le fue el último trimestre?',
            icon: Icons.event_outlined,
            feature: PlanFeature.earnings,
            ticker: ticker,
          ),
        if (!exclude.contains(fundamentals))
          QaFollowUp(
            'Fundamentals',
            'Pasame los fundamentals de $ticker',
            icon: Icons.analytics_outlined,
            feature: PlanFeature.fundamentals,
            ticker: ticker,
          ),
        if (!exclude.contains(compare))
          QaFollowUp(
            'vs. S&P 500',
            'Compará $ticker con el S&P 500 (VOO)',
            icon: Icons.compare_arrows_rounded,
          ),
      ];
}

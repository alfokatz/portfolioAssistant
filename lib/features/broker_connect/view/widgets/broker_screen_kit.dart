import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

// Las piezas que comparten las pantallas de conexión de brókers (eToro,
// Binance, SnapTrade). Antes cada pantalla tenía su copia privada: un ajuste
// visual había que repetirlo tres veces. Lo propio de cada bróker (textos,
// estados, la card de lo importado) queda en su pantalla.

/// La card de la app: blanca, borde fino, radio grande.
class BrokerCard extends StatelessWidget {
  const BrokerCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class BrokerCardDivider extends StatelessWidget {
  const BrokerCardDivider({
    super.key,
    required this.indent,
    required this.color,
  });

  final double indent;
  final Color color;

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: indent,
    endIndent: AppDimens.sp16,
    color: color,
  );
}

/// "Conectada" en verde o un aviso en rojo ([warn]), con su punto.
class BrokerStatusPill extends StatelessWidget {
  const BrokerStatusPill({super.key, required this.warn, required this.label});

  final bool warn;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final (fg, bg) =
        warn
            ? (colors.loss, colors.lossContainer)
            : (colors.profit, colors.profitContainer);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp8,
        vertical: AppDimens.sp4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppDimens.sp6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila label + valor de la card de estado.
class BrokerStatusRow extends StatelessWidget {
  const BrokerStatusRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp16,
        vertical: 14,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: tt.bodyMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BrokerTitleBody extends StatelessWidget {
  const BrokerTitleBody({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: tt.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          body,
          style: tt.bodySmall?.copyWith(
            color: colors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

/// Un círculo teñido con un ícono o un número, como en Ajustes.
class BrokerBubble extends StatelessWidget {
  const BrokerBubble({super.key, required this.child, this.size = 36});

  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.customColors.chip,
      shape: BoxShape.circle,
    ),
    child: child,
  );
}

/// Una línea chica con un candado, centrada (privacidad, plan).
class BrokerFootnote extends StatelessWidget {
  const BrokerFootnote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: AppDimens.sp4),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 13,
                color: colors.textSecondary,
              ),
            ),
          ),
          TextSpan(text: text),
        ],
      ),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: colors.textSecondary,
        height: 1.45,
      ),
    );
  }
}

/// El error de la última acción, debajo del botón (lo lee el lector de
/// pantalla al aparecer).
class BrokerInlineError extends StatelessWidget {
  const BrokerInlineError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: context.customColors.loss,
        height: 1.45,
      ),
    ),
  );
}

/// Salida secundaria de la pantalla bloqueada: traer la cartera con una
/// captura. Texto, no relleno: "Ver planes" sigue siendo lo primero.
class BrokerScreenshotExit extends StatelessWidget {
  const BrokerScreenshotExit({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Center(
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.photo_camera_outlined, size: AppDimens.iconMd),
        label: Text(label, textAlign: TextAlign.center),
        style: TextButton.styleFrom(
          foregroundColor: colors.accentBlue,
          minimumSize: const Size(48, 48),
        ),
      ),
    );
  }
}

/// Secundario: borde, sin relleno (como "Cerrar posición").
class BrokerSecondaryButton extends StatelessWidget {
  const BrokerSecondaryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: AppDimens.iconMd),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          backgroundColor: colors.surfaceCard,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// "¿Qué hacemos con lo importado?": quedárselo como manual (`true`) o
/// borrarlo (`false`). Se muestra en un bottom sheet; los textos son de
/// cada bróker.
class BrokerDisconnectSheet extends StatelessWidget {
  const BrokerDisconnectSheet({
    super.key,
    required this.title,
    required this.body,
    required this.keepLabel,
    required this.deleteLabel,
  });

  final String title;
  final String body;
  final String keepLabel;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: tt.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              body,
              style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppDimens.sp20),
            PositionPrimaryButton(
              label: keepLabel,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppDimens.sp8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.loss,
                  side: BorderSide(color: colors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  ),
                ),
                child: Text(deleteLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Arriba de la pantalla: Porty ↔ el bróker (el enlace cuenta el estado),
/// el título y una línea. Cada bróker decide los textos y el [link] según
/// su conexión.
class BrokerHeader extends StatelessWidget {
  const BrokerHeader({
    super.key,
    required this.partner,
    required this.link,
    required this.title,
    required this.body,
  });

  /// El logo del bróker (p. ej. `BinanceLogoTile`).
  final Widget partner;
  final EtoroLinkState link;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PortyPartnerLockup(state: link, partner: partner),
        const SizedBox(height: AppDimens.sp24),
        Semantics(
          header: true,
          child: Text(
            title,
            style: tt.displaySmall?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.2,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          body,
          style: tt.bodyMedium?.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// Lo que Porty promete antes de conectar (solo lectura, al día,
/// desconectar cuando quieras): ícono, título y cuerpo por punto.
class BrokerPromises extends StatelessWidget {
  const BrokerPromises({super.key, required this.points});

  final List<(IconData, String, String)> points;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return BrokerCard(
      child: Column(
        children: [
          for (final (i, (icon, title, body)) in points.indexed) ...[
            if (i > 0) BrokerCardDivider(indent: 64, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(AppDimens.sp16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrokerBubble(
                    child: Icon(icon, size: 18, color: colors.onChip),
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(child: BrokerTitleBody(title: title, body: body)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lo importado de una cuenta conectada: la pastilla de estado, la cifra en
/// grande, la última actualización, filas propias del bróker ([extraRows]),
/// lo que no se importó y el aviso del precio de compra estimado. Los
/// textos los arma cada bróker.
class BrokerStatusCard extends StatelessWidget {
  const BrokerStatusCard({
    super.key,
    required this.warn,
    required this.pillLabel,
    required this.importedCount,
    required this.importedLabel,
    required this.lastSyncLabel,
    required this.lastSyncValue,
    this.extraRows = const [],
    required this.notImportedTitle,
    this.notImportedBody,
    this.estimatedCostNote,
  });

  final bool warn;
  final String pillLabel;
  final int importedCount;
  final String importedLabel;
  final String lastSyncLabel;
  final String lastSyncValue;

  /// Van después de la última actualización, cada una con su divisor.
  final List<Widget> extraRows;
  final String notImportedTitle;

  /// `null`: no hay fila de "lo que no importé".
  final String? notImportedBody;

  /// `null`: no hay aviso de precio estimado.
  final String? estimatedCostNote;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final divider = BrokerCardDivider(
      indent: AppDimens.sp16,
      color: colors.border,
    );
    return BrokerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.sp16,
              AppDimens.sp16,
              AppDimens.sp16,
              AppDimens.sp12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrokerStatusPill(warn: warn, label: pillLabel),
                const SizedBox(height: AppDimens.sp16),
                Text(
                  '$importedCount',
                  style: tt.displaySmall?.copyWith(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    height: 1.1,
                    color: colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppDimens.sp2),
                Text(
                  importedLabel,
                  style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          divider,
          BrokerStatusRow(label: lastSyncLabel, value: lastSyncValue),
          for (final row in extraRows) ...[divider, row],
          if (notImportedBody case final body?) ...[
            divider,
            Padding(
              padding: const EdgeInsets.all(AppDimens.sp16),
              child: BrokerTitleBody(title: notImportedTitle, body: body),
            ),
          ],
          if (estimatedCostNote case final note?) ...[
            divider,
            Padding(
              padding: const EdgeInsets.all(AppDimens.sp16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: AppDimens.iconMd,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  Expanded(
                    child: Text(
                      note,
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

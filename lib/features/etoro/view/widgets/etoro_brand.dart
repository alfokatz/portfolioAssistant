import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_images.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Cómo está el enlace entre Porty y eToro en [EtoroPortyLockup].
enum EtoroLinkState {
  /// Sin conectar: línea punteada, Porty en reposo.
  idle,

  /// Conectada: línea llena con un check, Porty contento.
  linked,

  /// eToro cerró el acceso: la línea cortada, Porty preocupado.
  broken,
}

/// El wordmark de eToro sobre una card blanca, del alto de [height]. Es la
/// "cara" de eToro en sus pantallas, al lado de Porty.
class EtoroLogoTile extends StatelessWidget {
  const EtoroLogoTile({super.key, this.height = 56});

  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height * 0.3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(height * 0.3),
        border: Border.all(color: colors.border),
      ),
      child: AppImages.etoroLogo(height: height * 0.28),
    );
  }
}

/// El ícono de eToro como el de su app: "‹e›" verde sobre un círculo
/// oscuro (el mismo en tema claro y oscuro). Va donde la app pone un ícono
/// en círculo, como las filas de Ajustes.
class EtoroAppIcon extends StatelessWidget {
  const EtoroAppIcon({super.key, this.size = 36});

  final double size;

  static const _background = Color(0xFF151515);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _background,
        shape: BoxShape.circle,
      ),
      child: AppImages.etoroMark(width: size * 0.6),
    );
  }
}

/// Porty ↔ eToro: el avatar, el enlace y el logo. Encabeza las pantallas de
/// eToro y cuenta el estado de un vistazo (conectada, sin conectar, sin
/// acceso) antes de leer nada.
class EtoroPortyLockup extends StatelessWidget {
  const EtoroPortyLockup({
    super.key,
    required this.state,
    this.size = 56,
    this.animated = true,
  });

  final EtoroLinkState state;
  final double size;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final mood = switch (state) {
      EtoroLinkState.idle => PortyAvatarState.idle,
      EtoroLinkState.linked => PortyAvatarState.answered,
      EtoroLinkState.broken => PortyAvatarState.concerned,
    };
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PortyAvatar(size: size, state: mood, animated: animated),
          _Link(state: state, height: size),
          EtoroLogoTile(height: size),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.state, required this.height});

  final EtoroLinkState state;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final (lineColor, dotColor, icon, iconColor) = switch (state) {
      EtoroLinkState.idle => (
        colors.textSecondary.withValues(alpha: 0.45),
        colors.surfaceElevated,
        Icons.add_rounded,
        colors.textSecondary,
      ),
      EtoroLinkState.linked => (
        colors.profit.withValues(alpha: 0.5),
        colors.profit,
        Icons.check_rounded,
        colors.surfaceCard,
      ),
      EtoroLinkState.broken => (
        colors.loss.withValues(alpha: 0.45),
        colors.lossContainer,
        Icons.link_off_rounded,
        colors.loss,
      ),
    };
    final dot = (height * 0.4).clamp(18.0, 24.0);
    return SizedBox(
      width: height * 0.85,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _LinkLinePainter(
                color: lineColor,
                dashed: state == EtoroLinkState.idle,
                gap: state == EtoroLinkState.broken ? dot + 6 : 0,
              ),
            ),
          ),
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: colors.background, width: 2),
            ),
            child: Icon(icon, size: dot * 0.62, color: iconColor),
          ),
        ],
      ),
    );
  }
}

/// La línea horizontal del enlace: punteada (sin conectar), llena
/// (conectada) o con un hueco en el medio (cortada).
class _LinkLinePainter extends CustomPainter {
  const _LinkLinePainter({
    required this.color,
    required this.dashed,
    required this.gap,
  });

  final Color color;
  final bool dashed;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    const inset = AppDimens.sp4;
    final mid = size.width / 2;
    void segment(double from, double to) {
      if (!dashed) {
        canvas.drawLine(Offset(from, y), Offset(to, y), paint);
        return;
      }
      for (var x = from; x < to; x += 6) {
        canvas.drawLine(Offset(x, y), Offset((x + 2).clamp(x, to), y), paint);
      }
    }

    segment(inset, mid - gap / 2);
    segment(mid + gap / 2, size.width - inset);
  }

  @override
  bool shouldRepaint(_LinkLinePainter old) =>
      old.color != color || old.dashed != dashed || old.gap != gap;
}

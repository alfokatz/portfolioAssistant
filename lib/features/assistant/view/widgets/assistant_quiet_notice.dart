import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Aviso de la app en el lugar de una respuesta ([AssistantNotice]): texto
/// secundario, sin card ni color de alerta — no es un error ni una venta.
/// Entra con el mismo crossfade de fila que reemplaza al orbe (ver
/// `_buildMessageTile`), así que no tiene animación propia.
class AssistantQuietNotice extends StatelessWidget {
  const AssistantQuietNotice({super.key, required this.notice});

  final AssistantNotice notice;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (notice) {
      AssistantNotice.dailyLimit => (
        'assistant_daily_limit_title'.tr(),
        'assistant_daily_limit_body'.tr(),
      ),
    };
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: PortfolioColors.textSecondary,
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp12),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.schedule_rounded,
                size: 14,
                color: PortfolioColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('$title $body', style: style)),
          ],
        ),
      ),
    );
  }
}

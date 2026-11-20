import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

/// Por qué se reporta una respuesta de Porty.
enum AnswerReportReason { wrong, advice, offensive, other }

/// "¿Qué estuvo mal en mi respuesta?": se abre manteniendo apretada una
/// respuesta de Porty. Lo piden las tiendas para el contenido generado por
/// IA (Apple 1.2 y la política de IA generativa de Google). El reporte queda
/// en `product_events` (`ai_answer_reported`) con el comienzo de la
/// respuesta, para revisarlo.
class ReportAnswerSheet extends StatefulWidget {
  const ReportAnswerSheet({super.key});

  /// Largo máximo del extracto que se guarda (props de hasta 2 KB).
  static const excerptLength = 600;

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required String? surfaceId,
    required String answer,
  }) async {
    final reason = await showModalBottomSheet<AnswerReportReason>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const ReportAnswerSheet(),
    );
    if (reason == null) return;
    final text = answer.trim();
    ref.read(productEventsProvider).log(ProductEvent.aiAnswerReported, {
      'reason': reason.name,
      if (surfaceId != null) 'surface_id': surfaceId,
      if (text.isNotEmpty)
        'excerpt':
            text.length > excerptLength
                ? text.substring(0, excerptLength)
                : text,
    });
    ref
        .read(alertProvider.notifier)
        .showSuccess(message: 'assistant_report_thanks'.tr());
  }

  @override
  State<ReportAnswerSheet> createState() => _ReportAnswerSheetState();
}

class _ReportAnswerSheetState extends State<ReportAnswerSheet> {
  AnswerReportReason? _reason;

  static String _labelKey(AnswerReportReason r) => switch (r) {
    AnswerReportReason.wrong => 'assistant_report_reason_wrong',
    AnswerReportReason.advice => 'assistant_report_reason_advice',
    AnswerReportReason.offensive => 'assistant_report_reason_offensive',
    AnswerReportReason.other => 'assistant_report_reason_other',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
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
            PortySays(
              messageKey: 'report',
              mood: PortyAvatarState.concerned,
              message: Semantics(
                header: true,
                child: Text('assistant_report_title'.tr()),
              ),
              footnote: Text('assistant_report_body'.tr()),
            ),
            const SizedBox(height: AppDimens.sp12),
            RadioGroup<AnswerReportReason>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value),
              child: Column(
                children: [
                  for (final reason in AnswerReportReason.values)
                    RadioListTile<AnswerReportReason>(
                      value: reason,
                      contentPadding: EdgeInsets.zero,
                      activeColor: colors.accentBlue,
                      title: Text(
                        _labelKey(reason).tr(),
                        style: text.bodyLarge?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.sp12),
            PositionPrimaryButton(
              label: 'assistant_report_send'.tr(),
              onPressed:
                  _reason == null
                      ? null
                      : () => Navigator.of(context).pop(_reason),
            ),
            const SizedBox(height: AppDimens.sp4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  minimumSize: const Size(
                    AppDimens.touchTarget,
                    AppDimens.touchTarget,
                  ),
                ),
                child: Text('assistant_report_cancel'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

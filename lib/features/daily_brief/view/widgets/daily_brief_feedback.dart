import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';

/// "¿Te sirvió?": sí / no y, si no, por qué (tres motivos). Una sola
/// respuesta por apertura; después, un agradecimiento corto. No manda nada
/// por sí mismo: avisa por [onAnswer] (`useful`, `reason?`).
class DailyBriefFeedback extends StatefulWidget {
  const DailyBriefFeedback({super.key, required this.onAnswer});

  final void Function(bool useful, String? reason) onAnswer;

  /// Los motivos de `daily_brief_feedback.reason`.
  static const reasons = ['wrong', 'irrelevant', 'too_long'];

  @override
  State<DailyBriefFeedback> createState() => _DailyBriefFeedbackState();
}

enum _Step { ask, reason, thanks }

class _DailyBriefFeedbackState extends State<DailyBriefFeedback> {
  _Step _step = _Step.ask;

  void _answer(bool useful, [String? reason]) {
    widget.onAnswer(useful, reason);
    setState(() => _step = _Step.thanks);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final label = switch (_step) {
      _Step.ask => 'daily_brief_feedback_title',
      _Step.reason => 'daily_brief_feedback_reason_title',
      _Step.thanks => 'daily_brief_feedback_thanks',
    };
    final actions = switch (_step) {
      _Step.ask => [
        _Choice('daily_brief_feedback_yes'.tr(), () => _answer(true)),
        _Choice(
          'daily_brief_feedback_no'.tr(),
          () => setState(() => _step = _Step.reason),
        ),
      ],
      _Step.reason => [
        for (final r in DailyBriefFeedback.reasons)
          _Choice('daily_brief_feedback_reason_$r'.tr(), () => _answer(false, r)),
      ],
      _Step.thanks => const <Widget>[],
    };
    return MotionAwareSize(
      duration: const Duration(milliseconds: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.tr(),
            style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          if (actions.isNotEmpty)
            Wrap(
              spacing: AppDimens.sp8,
              runSpacing: AppDimens.sp4,
              children: actions,
            ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, AppDimens.touchTarget),
        foregroundColor: colors.accentBlue,
      ),
      child: Text(label),
    );
  }
}

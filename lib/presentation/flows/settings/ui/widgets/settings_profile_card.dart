import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

/// Quién sos, arriba de Ajustes: iniciales, nombre y email, y "Editar" para
/// cambiar el nombre (el email no se edita desde acá).
class SettingsProfileCard extends StatelessWidget {
  const SettingsProfileCard({
    super.key,
    required this.name,
    required this.email,
    required this.onSaveName,
  });

  /// `null` o vacío: todavía no cargó su nombre.
  final String? name;
  final String email;

  /// Guarda el nombre; `true` si salió bien (la hoja se cierra).
  final Future<bool> Function(String name) onSaveName;

  static String initials(String? name, String email) {
    final words =
        (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final letters = words.take(2).map((w) => w[0]).join();
    if (letters.isNotEmpty) return letters.toUpperCase();
    return email.isEmpty ? '?' : email[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final hasName = name?.trim().isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(AppDimens.cardPadding),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentBlue.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Text(
                initials(name, email),
                style: tt.titleMedium?.copyWith(
                  color: colors.accentBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasName ? name!.trim() : 'settings_profile_add_name'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(
                    color: hasName ? colors.textPrimary : colors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDimens.sp8),
          TextButton(
            onPressed: () => _edit(context),
            style: TextButton.styleFrom(
              foregroundColor: colors.accentBlue,
              minimumSize: const Size(
                AppDimens.touchTarget,
                AppDimens.touchTarget,
              ),
              textStyle: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            child: Text('settings_profile_edit'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditNameSheet(initial: name ?? '', onSave: onSaveName),
  );
}

class _EditNameSheet extends StatefulWidget {
  const _EditNameSheet({required this.initial, required this.onSave});

  final String initial;
  final Future<bool> Function(String name) onSave;

  static const maxLength = 60;

  @override
  State<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<_EditNameSheet> {
  late final _controller = TextEditingController(text: widget.initial.trim());
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'auth_full_name_required'.tr());
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onSave(name);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      // Sube con el teclado.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.sp24,
            AppDimens.sp20,
            AppDimens.sp24,
            AppDimens.sp20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'settings_profile_name_title'.tr(),
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimens.sp4),
              Text(
                'settings_profile_name_hint'.tr(),
                style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppDimens.sp16),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_saving,
                maxLength: _EditNameSheet.maxLength,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.name],
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'settings_full_name'.tr(),
                  errorText: _error,
                  counterText: '',
                ),
              ),
              const SizedBox(height: AppDimens.sp20),
              PositionPrimaryButton(
                label: 'save'.tr(),
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/investor_profile/nav/investor_profile_router.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_mode_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/nav/auth_router.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/auth_provider.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/nav/onboarding_router.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/providers/onboarding_provider.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_appearance_picker.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_danger_zone.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_nav_row.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_picker_sheet.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_profile_card.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_section_card.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_subscription_card.dart';
import 'package:url_launcher/url_launcher.dart';

const _appVersion = '1.0.0';

class SettingsScreen extends StatefulHookConsumerWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends BaseStatefulWidget<SettingsScreen> {
  // See HomeScreen: this tab stays mounted alongside Home and Assistant in
  // the shell's IndexedStack, so AppShell owns the single subscription.
  @override
  bool get subscribesToGlobalEvents => false;

  @override
  void initState() {
    runAfterPostFrameCallback(() {
      ref.read(investorProfileProvider.notifier).refresh();
    });
    super.initState();
  }

  String _languageLabel(Locale locale) {
    return locale.languageCode == 'es'
        ? 'settings_language_spanish'.tr()
        : 'settings_language_english'.tr();
  }

  Future<void> _showLanguagePicker() async {
    final current = context.locale;
    final selected = await showModalBottomSheet<Locale>(
      context: context,
      builder:
          (ctx) => SettingsPickerSheet(
            title: 'settings_language'.tr(),
            children: [
              SettingsPickerOption(
                label: 'settings_language_spanish'.tr(),
                isSelected: current.languageCode == 'es',
                onTap: () => Navigator.of(ctx).pop(const Locale('es', 'ES')),
              ),
              SettingsPickerOption(
                label: 'settings_language_english'.tr(),
                isSelected: current.languageCode == 'en',
                onTap: () => Navigator.of(ctx).pop(const Locale('en', 'US')),
              ),
            ],
          ),
    );

    if (selected != null && mounted) {
      await context.setLocale(selected);
    }
  }

  /// Guarda el nombre en la metadata del usuario (`full_name`). `false` si
  /// falló (la hoja queda abierta y se avisa).
  Future<bool> _saveName(String name) async {
    try {
      await ref.read(supabaseAuthServiceProvider).updateFullName(name);
      if (!mounted) return false;
      setState(() {}); // currentUser ya trae el nombre nuevo.
      return true;
    } catch (_) {
      if (mounted) {
        ref
            .read(alertProvider.notifier)
            .showError(message: 'settings_profile_name_error'.tr());
      }
      return false;
    }
  }

  String? _investorProfileLabel(InvestorProfileState state) {
    final profile = state.profile;
    if (profile == null) {
      return state.hasLoaded ? 'settings_investor_profile_empty'.tr() : null;
    }
    if (state.statusAt(DateTime.now()) == InvestorProfileStatus.stale) {
      return 'settings_investor_profile_review'.tr();
    }
    return '${'investor_profile_risk_${profile.risk.storageValue}'.tr()} · '
        '${'investor_profile_horizon_${profile.horizon.storageValue}'.tr()}';
  }

  Future<void> _onReplayOnboarding() async {
    await ref.read(onboardingProvider).reset();
    if (!mounted) return;
    context.goNamed(OnboardingRouter.routeName);
  }

  Future<void> _onChangePassword(String email) async {
    if (email.isEmpty || email == 'auth_no_email'.tr()) {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'auth_email_required'.tr());
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('settings_change_password'.tr()),
            content: Text('settings_change_password_message'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('cancel'.tr()),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('settings_send_link'.tr()),
              ),
            ],
          ),
    );

    if (confirmed != true || !mounted) return;

    await ref
        .read(authControllerProvider.notifier)
        .requestPasswordReset(email: email);
  }

  Future<void> _onSignOut() async {
    final error = await ref.read(authControllerProvider.notifier).signOut();
    if (error != null) {
      ref.read(alertProvider.notifier).showError(message: error.message);
      return;
    }
    if (mounted) {
      context.go(AuthRouter.loginPath);
    }
  }

  Future<void> _onDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = ctx.customColors;
        return AlertDialog(
          title: Text('settings_delete_account'.tr()),
          content: Text('settings_delete_account_message'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: colors.loss),
              child: Text('settings_delete_account'.tr()),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    ref
        .read(alertProvider.notifier)
        .showWarning(message: 'settings_delete_account_unavailable'.tr());
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'settings_link_error'.tr());
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final user = ref.watch(supabaseAuthServiceProvider).currentUser;
    final themeMode = ref.watch(themeModeProvider);
    final hapticsEnabled = ref.watch(hapticsEnabledProvider);
    final investorProfile = ref.watch(investorProfileProvider);

    final email = user?.email ?? 'auth_no_email'.tr();
    final metadata = user?.userMetadata;
    final fullName = (metadata?['full_name'] as String?)?.trim();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp8,
            AppDimens.pageHorizontal,
            // La barra de pestañas flota encima del final de la lista (el
            // shell usa `extendBody`, así que su alto viene en el padding de
            // abajo): sin esto, "Eliminar cuenta" quedaba tapado.
            AppDimens.sp32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, AppDimens.sp20),
              child: Semantics(
                header: true,
                child: Text(
                  'settings_title'.tr(),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: context.customColors.textPrimary,
                  ),
                ),
              ),
            ),
            SettingsProfileCard(
              name: fullName,
              email: email,
              onSaveName: _saveName,
            ),
            const SizedBox(height: AppDimens.sp16),
            SettingsSectionCard(
              title: 'settings_section_profile'.tr(),
              children: [
                SettingsNavRow(
                  icon: Icons.tune_rounded,
                  label: 'settings_investor_profile'.tr(),
                  subtitle: _investorProfileLabel(investorProfile),
                  onTap:
                      () => context.pushNamed(InvestorProfileRouter.routeName),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sectionGap),
            SettingsSectionCard(
              title: 'settings_section_preferences'.tr(),
              children: [
                SettingsNavRow(
                  icon: Icons.language_rounded,
                  label: 'settings_language'.tr(),
                  value: _languageLabel(context.locale),
                  onTap: _showLanguagePicker,
                ),
                const SettingsDivider(),
                SettingsNavRow(
                  icon: Icons.dark_mode_outlined,
                  label: 'settings_appearance'.tr(),
                  value: settingsAppearanceLabel(themeMode),
                  onTap: () => showSettingsAppearancePicker(context, ref),
                ),
                // Notificaciones y alertas de precio: se sacaron porque no
                // hacían nada; ver docs/backlog/notificaciones-y-alertas-de-precio.md.
                const SettingsDivider(),
                SettingsToggleRow(
                  icon: Icons.vibration_rounded,
                  label: 'settings_haptics'.tr(),
                  value: hapticsEnabled,
                  onChanged: ref.read(hapticsEnabledProvider.notifier).setEnabled,
                ),
                const SettingsDivider(),
                SettingsNavRow(
                  icon: Icons.play_lesson_outlined,
                  label: 'settings_replay_onboarding'.tr(),
                  onTap: _onReplayOnboarding,
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sectionGap),
            SettingsSectionCard(
              title: 'settings_section_security'.tr(),
              children: [
                SettingsNavRow(
                  icon: Icons.lock_reset_rounded,
                  label: 'settings_change_password'.tr(),
                  onTap: () => _onChangePassword(email),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sectionGap),
            const SettingsSubscriptionCard(),
            const SizedBox(height: AppDimens.sectionGap),
            SettingsSectionCard(
              title: 'settings_section_about'.tr(),
              children: [
                SettingsNavRow(
                  icon: Icons.info_outline_rounded,
                  label: 'settings_version'.tr(),
                  value: _appVersion,
                  showChevron: false,
                  onTap: null,
                ),
                const SettingsDivider(),
                SettingsNavRow(
                  icon: Icons.description_outlined,
                  label: 'settings_terms'.tr(),
                  onTap: () => _openUrl('https://portfolioai.app/terms'),
                ),
                const SettingsDivider(),
                SettingsNavRow(
                  icon: Icons.shield_outlined,
                  label: 'settings_privacy'.tr(),
                  onTap: () => _openUrl('https://portfolioai.app/privacy'),
                ),
                const SettingsDivider(),
                SettingsNavRow(
                  icon: Icons.star_outline_rounded,
                  label: 'settings_rate_app'.tr(),
                  onTap: () => _openUrl('https://portfolioai.app/rate'),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sectionGap),
            SettingsDangerZone(
              onSignOut: _onSignOut,
              onDeleteAccount: _onDeleteAccount,
            ),
          ],
        ),
      ),
    );
  }
}

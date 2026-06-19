import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/auth/nav/auth_router.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/auth_provider.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/nav/onboarding_router.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/providers/onboarding_provider.dart';
import 'package:portfolio_assistant/presentation/flows/settings/providers/settings_provider.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_danger_zone.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_nav_row.dart';
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
  @override
  void initState() {
    runAfterPostFrameCallback(() {
      ref.read(settingsProvider.notifier).init();
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
      backgroundColor: PortfolioColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              'settings_language'.tr(),
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    color: PortfolioColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            _LanguageOption(
              label: 'settings_language_spanish'.tr(),
              locale: const Locale('es', 'ES'),
              isSelected: current.languageCode == 'es',
            ),
            _LanguageOption(
              label: 'settings_language_english'.tr(),
              locale: const Locale('en', 'US'),
              isSelected: current.languageCode == 'en',
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      await context.setLocale(selected);
    }
  }

  Future<void> _showProfileSheet({
    required String title,
    required String value,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PortfolioColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      color: PortfolioColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                      color: PortfolioColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onReplayOnboarding() async {
    await ref.read(onboardingProvider).reset();
    if (!mounted) return;
    context.goNamed(OnboardingRouter.routeName);
  }

  Future<void> _onChangePassword(String email) async {
    if (email.isEmpty || email == 'auth_no_email'.tr()) {
      ref.read(alertProvider.notifier).showError(
            message: 'auth_email_required'.tr(),
          );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PortfolioColors.surfaceCard,
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

    await ref.read(authControllerProvider.notifier).requestPasswordReset(
          email: email,
        );
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
      builder: (ctx) => AlertDialog(
        backgroundColor: PortfolioColors.surfaceCard,
        title: Text('settings_delete_account'.tr()),
        content: Text('settings_delete_account_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF97316),
            ),
            child: Text('settings_delete_account'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    ref.read(alertProvider.notifier).showWarning(
          message: 'settings_delete_account_unavailable'.tr(),
        );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ref.read(alertProvider.notifier).showError(
            message: 'settings_link_error'.tr(),
          );
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final user = ref.watch(supabaseAuthServiceProvider).currentUser;
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final email = user?.email ?? 'auth_no_email'.tr();
    final metadata = user?.userMetadata;
    final fullName = (metadata?['full_name'] as String?)?.trim();
    final displayName = fullName?.isNotEmpty == true
        ? fullName!
        : 'settings_profile_name_placeholder'.tr();

    return Scaffold(
      backgroundColor: PortfolioColors.background,
      appBar: AppBar(
        title: Text('settings_title'.tr()),
        backgroundColor: PortfolioColors.background,
        foregroundColor: PortfolioColors.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SettingsSectionCard(
            title: 'settings_section_profile'.tr(),
            children: [
              SettingsNavRow(
                icon: Icons.person_outline_rounded,
                label: 'settings_full_name'.tr(),
                value: displayName,
                onTap: () => _showProfileSheet(
                  title: 'settings_full_name'.tr(),
                  value: displayName,
                ),
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Icons.mail_outline_rounded,
                label: 'auth_email'.tr(),
                value: email,
                onTap: () => _showProfileSheet(
                  title: 'auth_email'.tr(),
                  value: email,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
                icon: Icons.payments_outlined,
                label: 'settings_currency'.tr(),
                value: 'settings_currency_usd'.tr(),
                showChevron: false,
                onTap: null,
              ),
              const SettingsDivider(),
              SettingsToggleRow(
                icon: Icons.notifications_outlined,
                label: 'settings_notifications'.tr(),
                value: settings.notificationsEnabled,
                onChanged: settings.isLoading
                    ? null
                    : settingsNotifier.setNotificationsEnabled,
              ),
              const SettingsDivider(),
              SettingsToggleRow(
                icon: Icons.campaign_outlined,
                label: 'settings_price_alerts'.tr(),
                value: settings.priceAlertsEnabled,
                onChanged: settings.isLoading
                    ? null
                    : settingsNotifier.setPriceAlertsEnabled,
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Icons.play_lesson_outlined,
                label: 'settings_replay_onboarding'.tr(),
                onTap: _onReplayOnboarding,
              ),
            ],
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 24),
          const SettingsSubscriptionCard(),
          const SizedBox(height: 24),
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
          const SizedBox(height: 28),
          SettingsDangerZone(
            onSignOut: _onSignOut,
            onDeleteAccount: _onDeleteAccount,
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.locale,
    required this.isSelected,
  });

  final String label;
  final Locale locale;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          color: PortfolioColors.textPrimary,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_rounded, color: PortfolioColors.accentBlue)
          : null,
      onTap: () => Navigator.of(context).pop(locale),
    );
  }
}

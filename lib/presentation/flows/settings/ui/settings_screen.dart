import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateless_screen.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/auth/nav/auth_router.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/auth_provider.dart';

class SettingsScreen extends BaseStatelessScreen {
  SettingsScreen({super.key});

  @override
  Widget buildView(BuildContext context, WidgetRef ref) {
    final user = ref.watch(supabaseAuthServiceProvider).currentUser;
    final email = user?.email ?? 'auth_no_email'.tr();

    return Scaffold(
      backgroundColor: PortfolioColors.background,
      appBar: AppBar(
        title: Text('settings_title'.tr()),
        backgroundColor: PortfolioColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.mediumMargin),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'auth_signed_in_as'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PortfolioColors.textSecondary,
                  ),
            ),
            subtitle: Text(
              email,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: PortfolioColors.textPrimary,
                  ),
            ),
          ),
          const SizedBox(height: AppDimens.largeMargin),
          FilledButton(
            onPressed: () async {
              final error =
                  await ref.read(authControllerProvider.notifier).signOut();
              if (error != null) {
                ref.read(alertProvider.notifier).showError(
                      message: error.message,
                    );
                return;
              }
              if (context.mounted) {
                context.go(AuthRouter.loginPath);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: PortfolioColors.loss,
            ),
            child: Text('auth_sign_out'.tr()),
          ),
        ],
      ),
    );
  }
}

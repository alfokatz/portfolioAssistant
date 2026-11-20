import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_status_message.dart';

/// Lo que se ve si se abre una ruta que no existe (un link viejo, una
/// notificación de una versión anterior). Porty lo dice en su voz y lleva al
/// inicio; el error técnico va al log, nunca a la pantalla.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, this.error});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) debugPrint('[Router] $error');
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: PortyStatusMessage(
            mood: PortyAvatarState.concerned,
            title: 'error_page_title'.tr(),
            body: 'error_page_body'.tr(),
            actionLabel: 'error_page_action'.tr(),
            onAction: () => context.goNamed(HomeRouter.homeRouteName),
          ),
        ),
      ),
    );
  }
}

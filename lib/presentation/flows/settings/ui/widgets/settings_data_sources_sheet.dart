import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Fuentes de datos": de dónde salen las noticias, los resultados y los
/// fundamentals que muestra Porty, con atribución y link a cada fuente
/// (GDELT pide citarla; las citas de la búsqueda web se muestran en cada
/// respuesta).
class SettingsDataSourcesSheet extends StatelessWidget {
  const SettingsDataSourcesSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const SettingsDataSourcesSheet(),
  );

  static const sources = [
    (
      icon: Icons.account_balance_outlined,
      title: 'data_sources_sec_title',
      body: 'data_sources_sec_body',
      url: 'https://www.sec.gov/edgar',
    ),
    (
      icon: Icons.travel_explore_rounded,
      title: 'data_sources_web_title',
      body: 'data_sources_web_body',
      url: 'https://openai.com/policies/',
    ),
    (
      icon: Icons.public_rounded,
      title: 'data_sources_gdelt_title',
      body: 'data_sources_gdelt_body',
      url: 'https://www.gdeltproject.org/',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'data_sources_title'.tr(),
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'data_sources_intro'.tr(),
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 8),
            for (final s in sources)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: 10,
                leading: Icon(s.icon, color: colors.accentBlue),
                title: Text(
                  s.title.tr(),
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  s.body.tr(),
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                trailing: Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
                onTap: () => _open(s.url),
              ),
          ],
        ),
      ),
    );
  }

  static Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

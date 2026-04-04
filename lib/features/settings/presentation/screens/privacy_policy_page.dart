import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/legal_urls.dart';
import '../../../../core/theme/themed_content_surface.dart';

/// Документ открывается по кнопке — без экрана «вечной» загрузки и лишних перестроений.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static Uri get policyUri => Uri.parse(LegalUrls.site);

  Future<void> _openExternal(BuildContext context) async {
    final ok = await launchUrl(
      policyUri,
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть браузер')),
      );
    }
  }

  Future<void> _openInApp(BuildContext context) async {
    final ok = await launchUrl(
      policyUri,
      mode: LaunchMode.inAppWebView,
    );
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Встроенный просмотр недоступен — откройте во внешнем браузере'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: ThemedContentSurface.scaffold,
      appBar: AppBar(
        title: const Text('Политика конфиденциальности'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Документы размещены на официальном сайте приложения.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemedContentSurface.profileTextPrimary,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Выберите способ открытия. Сайт: ${LegalUrls.site}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ThemedContentSurface.profileTextSecondary,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _openExternal(context),
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('Открыть в браузере'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openInApp(context),
              icon: const Icon(Icons.web_rounded),
              label: const Text('Открыть в приложении'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 28),
            SelectableText(
              LegalUrls.site,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

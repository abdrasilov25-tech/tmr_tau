import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/themed_content_surface.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  /// Лендинг: папка `site/` → GitHub Actions → Pages (корень сайта без `/site/`).
  /// Репозиторий: `github.com/abdrasilov25-tech/tmr_tau`
  static const String privacyPolicyUrl =
      'https://abdrasilov25-tech.github.io/tmr_tau/';

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  bool _launchFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPolicy());
  }

  Future<void> _openPolicy() async {
    final uri = Uri.tryParse(PrivacyPolicyPage.privacyPolicyUrl);
    if (uri == null) return;

    final ok = await launchUrl(
      uri,
      mode: LaunchMode.inAppWebView,
    );

    if (!mounted) return;
    if (!ok) {
      setState(() => _launchFailed = true);
    }
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(PrivacyPolicyPage.privacyPolicyUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemedContentSurface.scaffold,
      appBar: AppBar(
        title: const Text('Политика конфиденциальности'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _launchFailed
              ? SingleChildScrollView(
                  key: const ValueKey('failed'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Не удалось открыть документ во встроенном просмотрщике.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _openExternal,
                        child: const Text('Открыть в браузере'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        PrivacyPolicyPage.privacyPolicyUrl,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                )
              : const Center(
                  key: ValueKey('loading'),
                  child: CircularProgressIndicator(),
                ),
        ),
      ),
    );
  }
}


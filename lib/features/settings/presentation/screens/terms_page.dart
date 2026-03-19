import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/themed_content_surface.dart';

class TermsPage extends StatefulWidget {
  const TermsPage({super.key});

  static const String termsUrl = 'https://example.com/terms';

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  bool _launchFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openTerms());
  }

  Future<void> _openTerms() async {
    final uri = Uri.tryParse(TermsPage.termsUrl);
    if (uri == null) return;

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) setState(() => _launchFailed = true);
  }

  Future<void> _retry() async {
    setState(() => _launchFailed = false);
    await _openTerms();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemedContentSurface.scaffold,
      appBar: AppBar(
        title: const Text('Условия сервиса'),
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
                        'Не удалось открыть условия сервиса.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _retry,
                        child: const Text('Повторить'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        TermsPage.termsUrl,
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


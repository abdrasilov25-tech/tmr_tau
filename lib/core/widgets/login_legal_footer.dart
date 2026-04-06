import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tmr_tau/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/legal_urls.dart';

/// Краткое согласие со ссылками на документы (ожидания стора / GDPR-style прозрачность).
class LoginLegalFooter extends StatefulWidget {
  const LoginLegalFooter({super.key});

  @override
  State<LoginLegalFooter> createState() => _LoginLegalFooterState();
}

class _LoginLegalFooterState extends State<LoginLegalFooter> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = _openTerms;
    _privacyTap = TapGestureRecognizer()..onTap = _openPrivacy;
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _openTerms() async {
    await launchUrl(
      Uri.parse(LegalUrls.termsUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openPrivacy() async {
    await launchUrl(
      Uri.parse(LegalUrls.privacyPolicyUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.72),
      fontSize: 12,
      height: 1.35,
    );
    final linkStyle = style.copyWith(
      color: const Color(0xFF00E5FF),
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: l10n.loginLegalPrefix),
          TextSpan(
            text: l10n.loginLegalTerms,
            style: linkStyle,
            recognizer: _termsTap,
          ),
          TextSpan(text: l10n.loginLegalMiddle),
          TextSpan(
            text: l10n.loginLegalPrivacy,
            style: linkStyle,
            recognizer: _privacyTap,
          ),
          TextSpan(text: l10n.loginLegalSuffix),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

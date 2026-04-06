/// Официальный сайт с правовыми документами и лендингом.
abstract final class LegalUrls {
  /// Полный базовый URL сайта (можно переопределить через --dart-define=LEGAL_SITE_URL=...)
  static const String site = String.fromEnvironment(
    'LEGAL_SITE_URL',
    defaultValue: 'https://temirtauapp09.atoms.world',
  );

  static Uri get siteUri => Uri.parse(site);

  static String get termsUrl {
    const override = String.fromEnvironment('LEGAL_TERMS_URL', defaultValue: '');
    return override.isEmpty ? '$site/terms' : override;
  }

  static String get privacyPolicyUrl {
    const override =
        String.fromEnvironment('LEGAL_PRIVACY_URL', defaultValue: '');
    return override.isEmpty ? '$site/privacy' : override;
  }

  /// Хосты HTTPS для App / Universal links (пути как в GoRouter).
  static Set<String> get deepLinkHosts {
    final h = siteUri.host;
    if (h.isEmpty) return const {};
    final set = {h};
    if (h.startsWith('www.')) {
      set.add(h.substring(4));
    } else {
      set.add('www.$h');
    }
    return set;
  }
}

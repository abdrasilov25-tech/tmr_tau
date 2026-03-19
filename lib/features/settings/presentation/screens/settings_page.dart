import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/themed_content_surface.dart';
import '../widgets/settings_expandable_section.dart';
import '../widgets/settings_item_tile.dart';

/// Main Settings screen with collapsible sections.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const String _privacyPolicyUrl =
      'https://abdrasilov25tech.github.io/tmr_tau/site/';
  static const String _termsUrl = 'https://example.com/terms';
  static const String _supportEmail = 'beksultanbekmurzaev75@gmail.com';

  Future<void> _openUrlInAppOrExternal(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // Основной сценарий: открываем в приложении.
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.inAppWebView,
    );

    // Если in-app webview недоступен — открываем в браузере.
    if (!ok && context.mounted) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemedContentSurface.scaffold,
      appBar: AppBar(
        title: const Text('Настройки'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 28),
        children: [
          SettingsExpandableSection(
            title: 'Аккаунт',
            icon: Icons.person_outline_rounded,
            initiallyExpanded: true,
            children: [
              SettingsItemTile(
                title: 'Редактировать профиль',
                icon: Icons.edit_outlined,
                onTap: () => context.push('/edit-profile'),
              ),
              SettingsItemTile(
                title: 'Сменить пароль',
                icon: Icons.lock_outline_rounded,
                onTap: () => context.push('/profile/settings/change-password'),
              ),
              SettingsItemTile(
                title: 'Подключенные аккаунты',
                icon: Icons.link_outlined,
                onTap: () =>
                    context.push('/profile/settings/connected-accounts'),
              ),
            ],
          ),
          SettingsExpandableSection(
            title: 'Приватность',
            icon: Icons.privacy_tip_outlined,
            children: [
              SettingsItemTile(
                title: 'Заблокированные пользователи',
                icon: Icons.block_outlined,
                onTap: () =>
                    context.push('/profile/settings/blocked-users'),
              ),
              SettingsItemTile(
                title: 'Статус активности',
                icon: Icons.circle_outlined,
                onTap: () =>
                    context.push('/profile/settings/activity-status'),
              ),
              SettingsItemTile(
                title: 'Кто видит сторис',
                icon: Icons.remove_red_eye_outlined,
                onTap: () =>
                    context.push('/profile/settings/story-controls'),
              ),
              SettingsItemTile(
                title: 'Видимость постов',
                icon: Icons.visibility_outlined,
                onTap: () =>
                    context.push('/profile/settings/post-visibility'),
              ),
            ],
          ),
          SettingsExpandableSection(
            title: 'Уведомления',
            icon: Icons.notifications_none_outlined,
            children: [
              SettingsItemTile(
                title: 'Push-уведомления',
                icon: Icons.notifications_active_outlined,
                onTap: () => context.push('/profile/settings/notifications'),
                subtitle: 'Настроить частоту и включение',
              ),
              SettingsItemTile(
                title: 'Email-уведомления',
                icon: Icons.mail_outline_rounded,
                onTap: () => context.push('/profile/settings/notifications'),
              ),
              SettingsItemTile(
                title: 'Внутри приложения',
                icon: Icons.smart_toy_outlined,
                onTap: () => context.push('/profile/settings/notifications'),
              ),
            ],
          ),
          SettingsExpandableSection(
            title: 'Безопасность',
            icon: Icons.shield_outlined,
            children: [
              SettingsItemTile(
                title: 'Двухфакторная аутентификация (2FA)',
                icon: Icons.security_update_outlined,
                onTap: () => context.push('/profile/settings/security'),
              ),
              SettingsItemTile(
                title: 'История входов',
                icon: Icons.history_outlined,
                onTap: () => context.push('/profile/settings/security'),
              ),
              SettingsItemTile(
                title: 'Управление сессиями',
                icon: Icons.logout_outlined,
                onTap: () => context.push('/profile/settings/security'),
              ),
            ],
          ),
          SettingsExpandableSection(
            title: 'Поддержка',
            icon: Icons.support_agent_outlined,
            children: [
              SettingsItemTile(
                title: 'Сообщить о проблеме',
                icon: Icons.report_problem_outlined,
                onTap: () =>
                    context.push('/profile/settings/report-problem'),
              ),
              SettingsItemTile(
                title: 'FAQ',
                icon: Icons.help_outline_rounded,
                onTap: () => context.push('/profile/settings/faq'),
              ),
              SettingsItemTile(
                title: 'Условия сервиса',
                icon: Icons.article_outlined,
                onTap: () => context.push('/profile/settings/terms'),
              ),
              SettingsItemTile(
                // Политика и контакты — добавляем в этот же блок,
                // чтобы остальные пункты настроек не менялись.
                title: 'Политика конфиденциальности',
                icon: Icons.privacy_tip,
                subtitle: 'Открыть документ',
                onTap: () => _openUrlInAppOrExternal(context, _privacyPolicyUrl),
              ),
              SettingsItemTile(
                title: 'Пользовательское соглашение',
                icon: Icons.article_outlined,
                subtitle: 'Открыть условия',
                onTap: () => _openUrlInAppOrExternal(context, _termsUrl),
              ),
              SettingsItemTile(
                title: 'Контакты',
                icon: Icons.mail_outline_rounded,
                subtitle: _supportEmail,
                onTap: () => launchUrl(
                  Uri.parse('mailto:$_supportEmail'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/themed_content_surface.dart';
import '../widgets/settings_expandable_section.dart';
import '../widgets/settings_item_tile.dart';

/// Main Settings screen with collapsible sections.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const String _supportEmail = 'Omirk82@gmail.com';
  static const String _whatsAppDisplay = '87084185801';
  /// 8… → международный 7… для wa.me
  static final Uri _whatsAppUri = Uri.parse('https://wa.me/77084185801');
  static final Uri _instagramUri = Uri.parse(
    'https://www.instagram.com/bekmurzaevbeksultan_?igsh=MTVzejdrYnVkbHUzdw==',
  );

  static const Color _whatsAppGreen = Color(0xFF25D366);
  static const Color _instagramPink = Color(0xFFE4405F);

  Future<void> _launchUri(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }

  Future<void> _showContactsDialog(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Контакты'),
        content: SelectableText(
          _supportEmail,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: scheme.primary,
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: const Text('Закрыть'),
          ),
          FilledButton.tonal(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _supportEmail));
              if (!context.mounted) return;
              Navigator.of(dCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Email скопирован')),
              );
            },
            child: const Text('Скопировать'),
          ),
          FilledButton(
            onPressed: () async {
              final uri = Uri.parse('mailto:$_supportEmail');
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (context.mounted) Navigator.of(dCtx).pop();
            },
            child: const Text('Написать'),
          ),
        ],
      ),
    );
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
              SettingsItemTile(
                title: 'Удалить аккаунт',
                icon: Icons.person_off_outlined,
                subtitle: 'Запрос через поддержку',
                onTap: () => context.push('/profile/settings/delete-account'),
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
                subtitle: 'Пользовательское соглашение на сайте',
                onTap: () => context.push('/profile/settings/terms'),
              ),
              SettingsItemTile(
                title: 'Политика конфиденциальности',
                icon: Icons.privacy_tip,
                subtitle: 'Сайт temirtauapp09.atoms.world',
                onTap: () => context.push('/profile/settings/privacy-policy'),
              ),
              SettingsItemTile(
                title: 'Email',
                icon: Icons.mail_outline_rounded,
                subtitle: _supportEmail,
                onTap: () => _showContactsDialog(context),
              ),
              SettingsItemTile(
                title: 'WhatsApp',
                icon: Icons.chat_rounded,
                subtitle: _whatsAppDisplay,
                customIcon: const FaIcon(
                  FontAwesomeIcons.whatsapp,
                  size: 24,
                  color: _whatsAppGreen,
                ),
                onTap: () => _launchUri(context, _whatsAppUri),
              ),
              SettingsItemTile(
                title: 'Instagram',
                icon: Icons.camera_alt_outlined,
                subtitle: '@bekmurzaevbeksultan_',
                customIcon: const FaIcon(
                  FontAwesomeIcons.instagram,
                  size: 24,
                  color: _instagramPink,
                ),
                onTap: () => _launchUri(context, _instagramUri),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


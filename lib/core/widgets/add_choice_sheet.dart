import 'package:flutter/material.dart';

/// Нижний лист при нажатии на «плюс»: Прувнуть, Сторис, Видео (как в Instagram).
class AddChoiceSheet extends StatelessWidget {
  const AddChoiceSheet({
    super.key,
    required this.onProuvnut,
    required this.onStory,
    required this.onVideo,
  });

  final VoidCallback onProuvnut;
  final VoidCallback onStory;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 28),
              _OptionTile(
                icon: Icons.grid_on_rounded,
                title: 'Прувнуть',
                subtitle: 'Публикация в ленту',
                onTap: onProuvnut,
              ),
              const Divider(color: Colors.white12, height: 1),
              _OptionTile(
                icon: Icons.auto_awesome_rounded,
                title: 'Сторис',
                subtitle: 'Для выкладывания историй',
                onTap: onStory,
              ),
              const Divider(color: Colors.white12, height: 1),
              _OptionTile(
                icon: Icons.videocam_rounded,
                title: 'Видео',
                subtitle: 'Загрузка видео не более 2 минут',
                onTap: onVideo,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 13,
        ),
      ),
      onTap: onTap,
    );
  }
}

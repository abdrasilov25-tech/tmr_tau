import 'package:flutter/material.dart';

import '../../../../core/theme/themed_content_surface.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemedContentSurface.scaffold,
      appBar: AppBar(
        title: const Text('FAQ'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          _FaqTile(
            title: 'Как изменить пароль?',
            content: 'Откройте раздел «Сменить пароль» в настройках. Мы отправим ссылку на email.',
          ),
          _FaqTile(
            title: 'Как управлять приватностью?',
            content: 'Откройте «Приватность» и выберите, кто видит сторис и посты.',
          ),
          _FaqTile(
            title: 'Где посмотреть историю входов?',
            content: 'Раздел «Безопасность» -> «История входов». В демо-режиме может быть пусто.',
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(title),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(content),
          )
        ],
      ),
    );
  }
}


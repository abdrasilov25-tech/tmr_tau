import 'package:flutter/material.dart';

import '../../../../core/theme/themed_content_surface.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemedContentSurface.scaffold,
      appBar: AppBar(
        title: const Text('Условия сервиса'),
        centerTitle: true,
      ),
      body: const Padding(
        padding: EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Text(
            'Здесь должны быть условия сервиса.\n\n'
            'В текущей версии это заглушка UI, чтобы вы могли подключить текст после согласования.',
          ),
        ),
      ),
    );
  }
}


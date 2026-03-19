import 'package:flutter/material.dart';

import '../../../../core/theme/themed_content_surface.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemedContentSurface.scaffold,
      appBar: AppBar(
        title: const Text('Политика конфиденциальности'),
        centerTitle: true,
      ),
      body: const Padding(
        padding: EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Text(
            'Здесь должна находиться политика конфиденциальности.\n\n'
            'В текущей версии это заглушка UI.',
          ),
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';

class LiveStreamPage extends StatelessWidget {
  const LiveStreamPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Прямой эфир'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_tethering_rounded,
                size: 72,
                color: Colors.white70,
              ),
              const SizedBox(height: 14),
              const Text(
                'Прямой эфир скоро',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Подготовили раздел для запусков как в Instagram. Следующий шаг — подключение камеры и трансляции.',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StartChatButton extends StatelessWidget {
  const StartChatButton({
    super.key,
    required this.peerId,
    required this.peerName,
  });

  final String peerId;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () {
        final encodedName = Uri.encodeComponent(peerName);
        context.push('/chat/$peerId?name=$encodedName');
      },
      icon: const Icon(Icons.chat_bubble_outline),
      label: const Text('Написать'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}


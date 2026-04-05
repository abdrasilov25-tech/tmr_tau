import 'package:flutter/material.dart';

import '../../domain/entities/map_quest.dart';

/// Full quest sheet — shows all quests with progress, rewards, and Quest Pass CTA.
class MapQuestSheet extends StatelessWidget {
  const MapQuestSheet({
    super.key,
    required this.progress,
    required this.onQuestPassTap,
  });

  final MapQuestProgress progress;
  final VoidCallback onQuestPassTap;

  @override
  Widget build(BuildContext context) {
    final freeQuests =
        MapQuestDefinition.all.where((q) => !q.requiresQuestPass).toList();
    final passQuests =
        MapQuestDefinition.all.where((q) => q.requiresQuestPass).toList();
    final totalFreeReward = freeQuests.fold(0, (s, q) => s + q.reward);
    final totalPassReward = passQuests.fold(0, (s, q) => s + q.reward);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('⚡', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ежедневные квесты',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Сбрасываются каждые сутки в 00:00 UTC',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
                const Spacer(),
                // Today earnings chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF9C3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.toll_rounded,
                          size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Text(
                        '+${progress.totalEarnedToday}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _QuestProgressBar(progress: progress),
          ),
          const SizedBox(height: 16),
          // Free quests
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Бесплатно',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'до +$totalFreeReward Qarmet',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF166534),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...freeQuests.map((q) => _QuestTile(
                quest: q,
                isDone: progress.isCompleted(q.id),
                isLocked: false,
              )),
          const SizedBox(height: 16),
          // Quest Pass section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Quest Pass',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF9C3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '+$totalPassReward Qarmet',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (!progress.hasQuestPass)
                  GestureDetector(
                    onTap: onQuestPassTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Подключить',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...passQuests.map((q) => _QuestTile(
                quest: q,
                isDone: progress.isCompleted(q.id),
                isLocked: !progress.hasQuestPass,
              )),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _QuestProgressBar extends StatelessWidget {
  const _QuestProgressBar({required this.progress});

  final MapQuestProgress progress;

  @override
  Widget build(BuildContext context) {
    final total = MapQuestDefinition.all.length;
    final done = progress.completedCount;
    final fraction = total == 0 ? 0.0 : done / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$done / $total квестов выполнено',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Сегодня: ${progress.totalEarnedToday} Qarmet',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFF59E0B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
          ),
        ),
      ],
    );
  }
}

class _QuestTile extends StatelessWidget {
  const _QuestTile({
    required this.quest,
    required this.isDone,
    required this.isLocked,
  });

  final MapQuestDefinition quest;
  final bool isDone;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDone
              ? const Color(0xFFF0FDF4)
              : isLocked
                  ? Colors.grey.shade50
                  : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDone
                ? const Color(0xFF86EFAC)
                : isLocked
                    ? Colors.grey.shade200
                    : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            // Status icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                    : isLocked
                        ? Colors.grey.shade200
                        : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isDone
                    ? Icons.check_circle_rounded
                    : isLocked
                        ? Icons.lock_rounded
                        : Icons.radio_button_unchecked_rounded,
                color: isDone
                    ? const Color(0xFF16A34A)
                    : isLocked
                        ? Colors.grey.shade400
                        : const Color(0xFFF59E0B),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quest.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isLocked ? Colors.grey.shade400 : Colors.black87,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    quest.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isLocked ? Colors.grey.shade300 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Reward
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '+${quest.reward}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDone
                        ? const Color(0xFF16A34A)
                        : isLocked
                            ? Colors.grey.shade300
                            : const Color(0xFFF59E0B),
                  ),
                ),
                Text(
                  'Qarmet',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

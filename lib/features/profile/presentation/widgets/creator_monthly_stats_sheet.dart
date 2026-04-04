import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/formatting/compact_count_format.dart';
import '../../domain/entities/creator_monthly_stats.dart';
import '../../domain/repositories/profile_repository.dart';

/// Нижняя панель со статистикой создателя (подписка Official Page), в духе Instagram Insights.
Future<void> showCreatorMonthlyStatsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _CreatorMonthlyStatsSheet(),
  );
}

class _CreatorMonthlyStatsSheet extends StatelessWidget {
  const _CreatorMonthlyStatsSheet();

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1A1A2E),
                Color(0xFF16213E),
                Color(0xFF0F0F1A),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: FutureBuilder<CreatorMonthlyStats>(
              future: context.read<ProfileRepository>().getCreatorMonthlyStats(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator(
                        color: Color(0xFFE8C547),
                        strokeWidth: 2.5,
                      ),
                    ),
                  );
                }
                final data = snapshot.data;
                if (data == null || !data.eligible) {
                  return _IneligibleBody(
                    scrollController: scrollController,
                    bottomPadding: bottom,
                  );
                }
                return _StatsBody(
                  stats: data,
                  scrollController: scrollController,
                  bottomPadding: bottom,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _IneligibleBody extends StatelessWidget {
  const _IneligibleBody({
    required this.scrollController,
    required this.bottomPadding,
  });

  final ScrollController scrollController;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomPadding),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Icon(Icons.workspace_premium_outlined,
            size: 48, color: Color(0xFFE8C547)),
        const SizedBox(height: 16),
        Text(
          'Статистика профиля',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          'Доступна с подпиской Official Page: просмотры ленты, взаимодействия, новые подписчики и публикации за 30 дней.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            height: 1.45,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({
    required this.stats,
    required this.scrollController,
    required this.bottomPadding,
  });

  final CreatorMonthlyStats stats;
  final ScrollController scrollController;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPadding),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFBF953F), Color(0xFFFCF6BA), Color(0xFFB38728)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  color: Color(0xFF1A1A2E),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'За последние ${stats.periodDays} дней',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Как в профессиональных инструментах: охват контента и активность аудитории.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 22),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: [
            _MetricTile(
              icon: Icons.visibility_rounded,
              label: 'Просмотры',
              subtitle: 'Показы ваших постов в ленте',
              value: formatCompactCount(stats.profileViews),
              accent: const Color(0xFF7C6CF9),
            ),
            _MetricTile(
              icon: Icons.favorite_rounded,
              label: 'Взаимодействия',
              subtitle: 'Лайки, комментарии, репосты',
              value: formatCompactCount(stats.interactions),
              accent: const Color(0xFFE879A9),
            ),
            _MetricTile(
              icon: Icons.person_add_alt_1_rounded,
              label: 'Новые подписчики',
              subtitle: 'За выбранный период',
              value: formatCompactCount(stats.newFollowers),
              accent: const Color(0xFF4ADE80),
            ),
            _MetricTile(
              icon: Icons.grid_on_rounded,
              label: 'Ваш контент',
              subtitle: 'Публикаций за период',
              value: formatCompactCount(stats.sharedPosts),
              accent: const Color(0xFF38BDF8),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.5), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Цифры обновляются по мере активности в приложении. Просмотры считаются по времени в ленте публикаций.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

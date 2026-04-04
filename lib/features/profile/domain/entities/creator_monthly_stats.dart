import 'package:equatable/equatable.dart';

/// Ответ RPC [get_creator_monthly_stats] для подписчиков Official Page.
class CreatorMonthlyStats extends Equatable {
  const CreatorMonthlyStats({
    required this.eligible,
    this.periodDays = 30,
    this.profileViews = 0,
    this.interactions = 0,
    this.newFollowers = 0,
    this.sharedPosts = 0,
  });

  final bool eligible;
  final int periodDays;
  final int profileViews;
  final int interactions;
  final int newFollowers;
  final int sharedPosts;

  @override
  List<Object?> get props => [
        eligible,
        periodDays,
        profileViews,
        interactions,
        newFollowers,
        sharedPosts,
      ];
}

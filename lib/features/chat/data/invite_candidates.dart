import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/supabase_constants.dart';

/// Кандидаты для приглашения в группу: подписчики и подписки (не только взаимные).
class InviteCandidate {
  const InviteCandidate({
    required this.id,
    required this.name,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? avatarUrl;
}

Future<List<InviteCandidate>> loadInviteCandidates(
  SupabaseClient client,
  String currentUserId,
) async {
  final myFollowingRes = await client
      .from(SupabaseConstants.followersTable)
      .select('following_id')
      .eq('follower_id', currentUserId);
  final myFollowersRes = await client
      .from(SupabaseConstants.followersTable)
      .select('follower_id')
      .eq('following_id', currentUserId);

  final followingIds = (myFollowingRes as List)
      .map((e) => (e as Map<String, dynamic>)['following_id'] as String?)
      .whereType<String>()
      .toSet();
  final followerIds = (myFollowersRes as List)
      .map((e) => (e as Map<String, dynamic>)['follower_id'] as String?)
      .whereType<String>()
      .toSet();

  final candidateIds = {...followingIds, ...followerIds}..remove(currentUserId);
  if (candidateIds.isEmpty) return const [];

  final usersRes = await client
      .from(SupabaseConstants.usersTable)
      .select('id,name,avatar')
      .inFilter('id', candidateIds.toList(growable: false))
      .order('name');

  return (usersRes as List)
      .map((e) => e as Map<String, dynamic>)
      .map(
        (j) => InviteCandidate(
          id: j['id'] as String,
          name: (j['name'] as String?)?.trim().isNotEmpty == true
              ? (j['name'] as String)
              : 'Пользователь',
          avatarUrl: j['avatar'] as String?,
        ),
      )
      .toList(growable: false);
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/supabase_constants.dart';

/// Операции владельца канала (RPC и обновление метаданных).
class ChannelOwnerApi {
  ChannelOwnerApi._();

  static Future<void> inviteUsers(
    SupabaseClient client, {
    required String channelId,
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) return;
    await client.rpc(
      'channel_owner_invite_users',
      params: {
        'p_channel_id': channelId,
        'p_user_ids': userIds,
      },
    );
  }

  static Future<void> updateChannelSettings(
    SupabaseClient client, {
    required String channelId,
    required String ownerId,
    String? title,
    String? description,
    bool? signPosts,
    bool? showLinkPreview,
    bool? silentBroadcast,
  }) async {
    final patch = <String, dynamic>{};
    if (title != null) patch['title'] = title;
    if (description != null) patch['description'] = description;
    if (signPosts != null) patch['sign_posts'] = signPosts;
    if (showLinkPreview != null) patch['show_link_preview'] = showLinkPreview;
    if (silentBroadcast != null) patch['silent_broadcast'] = silentBroadcast;
    if (patch.isEmpty) return;
    await client
        .from(SupabaseConstants.userChannelsTable)
        .update(patch)
        .eq('id', channelId)
        .eq('owner_id', ownerId);
  }
}

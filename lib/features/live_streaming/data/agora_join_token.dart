import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/agora_live_config.dart';
import 'datasources/agora_rtc_token_datasource.dart';

/// Статический токен из .env или выпуск через Edge Function (если токен в .env пустой).
Future<String> resolveAgoraJoinToken(
  SupabaseClient client, {
  required String channelName,
  required int uid,
  required bool publisher,
}) async {
  final staticToken = AgoraLiveConfig.token;
  if (staticToken.isNotEmpty) return staticToken;
  final fromEdge = await AgoraRtcTokenDatasource(client).fetchRtcToken(
    channelName: channelName,
    uid: uid,
    publisher: publisher,
  );
  return fromEdge ?? '';
}

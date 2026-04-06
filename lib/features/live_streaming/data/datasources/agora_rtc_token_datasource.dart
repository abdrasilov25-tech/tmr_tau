import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Запрос RTC-токена у Edge Function [agora-rtc-token].
class AgoraRtcTokenDatasource {
  AgoraRtcTokenDatasource(this._client);

  final SupabaseClient _client;

  Future<String?> fetchRtcToken({
    required String channelName,
    required int uid,
    required bool publisher,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'agora-rtc-token',
        body: <String, dynamic>{
          'channel_name': channelName,
          'uid': uid,
          'role': publisher ? 'publisher' : 'subscriber',
        },
      );
      final data = res.data;
      if (data is Map && data['token'] is String) {
        return data['token'] as String;
      }
    } catch (e) { debugPrint('$e'); }
    return null;
  }
}

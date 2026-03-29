import 'package:shared_preferences/shared_preferences.dart';

class HiddenPostsStorage {
  HiddenPostsStorage._();

  static const String _key = 'tmr_tau_hidden_post_ids';

  static Future<Set<String>> getHiddenPostIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key)?.toSet() ?? <String>{};
  }

  static Future<void> hidePost(String postId) async {
    if (postId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key)?.toSet() ?? <String>{};
    current.add(postId);
    await prefs.setStringList(_key, current.toList(growable: false));
  }

  static Future<void> unhidePost(String postId) async {
    if (postId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key)?.toSet() ?? <String>{};
    current.remove(postId);
    await prefs.setStringList(_key, current.toList(growable: false));
  }
}

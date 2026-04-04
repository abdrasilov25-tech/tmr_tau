/// Стабильный положительный uid для Agora (не 0), из UUID пользователя Supabase.
int agoraUidFromUserId(String userId) {
  final h = userId.replaceAll('-', '');
  if (h.length < 8) return 1;
  var x = int.tryParse(h.substring(0, 8), radix: 16) ?? 1;
  if (x <= 0) x = 1;
  return x;
}

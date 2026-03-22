import 'package:url_launcher/url_launcher.dart';

/// Убирает всё кроме цифр и ведущего [+] для отображения / набора.
String digitsForDial(String input) {
  final buf = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c == '+' && buf.isEmpty) {
      buf.write(c);
      continue;
    }
    if (RegExp(r'\d').hasMatch(c)) buf.write(c);
  }
  return buf.toString();
}

/// Ссылка [tel:] для Казахстана/РФ: 10 цифр → +7…, 11 с 7/8 в начале → +7…
Uri? telUriFromUserPhone(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final s = digitsForDial(t);
  String? e164;
  if (s.startsWith('+')) {
    final rest = s.substring(1);
    if (rest.length >= 9) e164 = '+$rest';
  } else if (s.length == 11 && (s.startsWith('7') || s.startsWith('8'))) {
    e164 = '+7${s.substring(1)}';
  } else if (s.length == 10) {
    e164 = '+7$s';
  } else if (s.length >= 9) {
    e164 = '+$s';
  }
  if (e164 == null) return null;
  return Uri.parse('tel:${Uri.encodeComponent(e164)}');
}

Future<bool> launchPhoneCall(String raw) async {
  final uri = telUriFromUserPhone(raw);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

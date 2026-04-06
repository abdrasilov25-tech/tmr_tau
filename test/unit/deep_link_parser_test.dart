import 'package:flutter_test/flutter_test.dart';
import 'package:tmr_tau/core/deep_link/deep_link_parser.dart';

void main() {
  const hosts = {'temirtauapp09.atoms.world', 'www.temirtauapp09.atoms.world'};

  test('https product path -> GoRouter location', () {
    final u = Uri.parse('https://temirtauapp09.atoms.world/product/abc?mention=x');
    expect(deepLinkToGoLocation(u, httpsHosts: hosts), '/product/abc?mention=x');
  });

  test('tmrtau scheme path', () {
    final u = Uri.parse('tmrtau:///post/123');
    expect(deepLinkToGoLocation(u, httpsHosts: hosts), '/post/123');
  });

  test('auth callback ignored', () {
    final u = Uri.parse('tmrtau://auth/callback?code=1');
    expect(deepLinkToGoLocation(u, httpsHosts: hosts), isNull);
  });

  test('foreign https host rejected', () {
    final u = Uri.parse('https://evil.example/product/1');
    expect(deepLinkToGoLocation(u, httpsHosts: hosts), isNull);
  });

  test('https root rejected', () {
    final u = Uri.parse('https://temirtauapp09.atoms.world/');
    expect(deepLinkToGoLocation(u, httpsHosts: hosts), isNull);
  });
}

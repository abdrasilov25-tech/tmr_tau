/// Преобразует входящий URI в location для [GoRouter] или null, если не наш формат.
String? deepLinkToGoLocation(
  Uri uri, {
  required Set<String> httpsHosts,
}) {
  if (uri.scheme == 'tmrtau') {
    if (uri.host == 'auth') {
      return null;
    }
    var path = uri.path;
    if (path.isEmpty && uri.host.isNotEmpty && uri.host != 'auth') {
      path = '/${uri.host}';
    }
    if (path.isEmpty || path == '/') {
      return null;
    }
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    final q = uri.hasQuery ? '?${uri.query}' : '';
    return '$path$q';
  }

  if (uri.scheme == 'https' || uri.scheme == 'http') {
    if (!httpsHosts.contains(uri.host)) {
      return null;
    }
    var path = uri.path;
    if (path.isEmpty || path == '/') {
      return null;
    }
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    final q = uri.hasQuery ? '?${uri.query}' : '';
    return '$path$q';
  }

  return null;
}

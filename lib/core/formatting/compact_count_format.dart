/// Короткий формат чисел в духе Instagram (1.2K, 3.4M).
String formatCompactCount(int n) {
  if (n < 0) return '0';
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final k = n / 1000;
    final rounded = k.round();
    if ((rounded - k).abs() < 0.05) return '${rounded}K';
    return '${k.toStringAsFixed(1)}K';
  }
  final m = n / 1000000;
  final rounded = m.round();
  if ((rounded - m).abs() < 0.05) return '${rounded}M';
  return '${m.toStringAsFixed(1)}M';
}

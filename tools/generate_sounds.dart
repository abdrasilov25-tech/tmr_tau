// dart run tools/generate_sounds.dart
//
// Generates short UI sound assets into assets/sounds/.
// Each sound is a PCM-16 mono WAV at 22050 Hz.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// ─── WAV writer ────────────────────────────────────────────────────────────────

Uint8List buildWav(List<double> samples, {int sampleRate = 22050}) {
  final numSamples = samples.length;
  final dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
  final fileSize = 36 + dataSize;

  final buf = ByteData(44 + dataSize);
  int off = 0;

  // RIFF header
  _setFourCC(buf, off, 'RIFF'); off += 4;
  buf.setUint32(off, fileSize, Endian.little); off += 4;
  _setFourCC(buf, off, 'WAVE'); off += 4;

  // fmt chunk
  _setFourCC(buf, off, 'fmt '); off += 4;
  buf.setUint32(off, 16, Endian.little); off += 4;     // chunk size
  buf.setUint16(off, 1, Endian.little); off += 2;      // PCM
  buf.setUint16(off, 1, Endian.little); off += 2;      // mono
  buf.setUint32(off, sampleRate, Endian.little); off += 4;
  buf.setUint32(off, sampleRate * 2, Endian.little); off += 4; // byte rate
  buf.setUint16(off, 2, Endian.little); off += 2;      // block align
  buf.setUint16(off, 16, Endian.little); off += 2;     // bits/sample

  // data chunk
  _setFourCC(buf, off, 'data'); off += 4;
  buf.setUint32(off, dataSize, Endian.little); off += 4;

  for (int i = 0; i < numSamples; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    buf.setInt16(off, (clamped * 32767).round(), Endian.little);
    off += 2;
  }

  return buf.buffer.asUint8List();
}

void _setFourCC(ByteData buf, int offset, String s) {
  for (int i = 0; i < 4; i++) {
    buf.setUint8(offset + i, s.codeUnitAt(i));
  }
}

// ─── Envelope helpers ─────────────────────────────────────────────────────────

/// Linear fade-in for [attackSamples], fade-out for [releaseSamples].
double envelope(int i, int total, int attackSamples, int releaseSamples) {
  if (i < attackSamples) return i / attackSamples;
  final releaseStart = total - releaseSamples;
  if (i >= releaseStart) return (total - i) / releaseSamples;
  return 1.0;
}

// ─── Sound generators ─────────────────────────────────────────────────────────

/// success.wav — ascending two-tone chime (C5 → E5), 220 ms
List<double> genSuccess({int sampleRate = 22050}) {
  final durationMs = 220;
  final n = (sampleRate * durationMs ~/ 1000);
  final halfway = n ~/ 2;
  final samples = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final freq = i < halfway ? 523.25 : 659.25; // C5 → E5
    final phase = 2 * math.pi * freq * i / sampleRate;
    final env = envelope(i, n, sampleRate * 10 ~/ 1000, sampleRate * 60 ~/ 1000);
    samples[i] = math.sin(phase) * env * 0.55;
  }
  return samples;
}

/// error.wav — low descending buzz (A3 → F3), 200 ms
List<double> genError({int sampleRate = 22050}) {
  final durationMs = 200;
  final n = (sampleRate * durationMs ~/ 1000);
  final samples = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final t = i / n;
    final freq = 220.0 - t * 55.0; // 220 Hz → 165 Hz
    final phase = 2 * math.pi * freq * i / sampleRate;
    final env = envelope(i, n, sampleRate * 8 ~/ 1000, sampleRate * 80 ~/ 1000);
    // Add slight harshness with a partial harmonic
    final s = math.sin(phase) * 0.7 + math.sin(phase * 2) * 0.2;
    samples[i] = s * env * 0.5;
  }
  return samples;
}

/// message_sent.wav — soft upward chirp, 150 ms
List<double> genMessageSent({int sampleRate = 22050}) {
  final durationMs = 150;
  final n = sampleRate * durationMs ~/ 1000;
  final samples = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final t = i / n;
    final freq = 400.0 + t * 400.0; // 400 → 800 Hz
    final phase = 2 * math.pi * freq * i / sampleRate;
    final env = envelope(i, n, sampleRate * 5 ~/ 1000, sampleRate * 70 ~/ 1000);
    samples[i] = math.sin(phase) * env * 0.45;
  }
  return samples;
}

/// message_received.wav — soft "pop" / bubble, 120 ms
List<double> genMessageReceived({int sampleRate = 22050}) {
  final durationMs = 120;
  final n = sampleRate * durationMs ~/ 1000;
  final samples = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final t = i / n;
    // Descending pop: starts high, quickly falls off
    final freq = 900.0 * math.exp(-t * 4.0) + 300.0;
    final phase = 2 * math.pi * freq * i / sampleRate;
    final env = envelope(i, n, sampleRate * 3 ~/ 1000, sampleRate * 50 ~/ 1000);
    samples[i] = math.sin(phase) * env * 0.5;
  }
  return samples;
}

// ─── Wow entry sounds ─────────────────────────────────────────────────────────

/// wow_battle.wav — sharp impact hit + low rumble boom, 380 ms
List<double> genWowBattle({int sampleRate = 22050}) {
  final n = sampleRate * 380 ~/ 1000;
  final samples = List<double>.filled(n, 0.0);
  for (int i = 0; i < n; i++) {
    final t = i / sampleRate;
    // Sharp high crack (freq sweeps 600→100 fast)
    final freq1 = 600.0 * math.exp(-t * 14) + 100.0;
    final s1 = math.sin(2 * math.pi * freq1 * t) * math.exp(-t * 6) * 0.55;
    // Low boom
    final s2 = math.sin(2 * math.pi * 75.0 * t) * math.exp(-t * 5) * 0.45;
    // Metallic harmonic
    final s3 = math.sin(2 * math.pi * 220.0 * t) * math.exp(-t * 9) * 0.2;
    final env = envelope(i, n, sampleRate * 4 ~/ 1000, sampleRate * 120 ~/ 1000);
    samples[i] = (s1 + s2 + s3) * env;
  }
  return samples;
}

/// wow_shop.wav — magical ascending arpeggio (C4 E4 G4 C5 E5), 420 ms
List<double> genWowShop({int sampleRate = 22050}) {
  const notes = [261.6, 329.6, 392.0, 523.3, 659.3];
  final n = sampleRate * 420 ~/ 1000;
  final samples = List<double>.filled(n, 0.0);
  final noteDur = n ~/ notes.length;
  for (int ni = 0; ni < notes.length; ni++) {
    final freq = notes[ni];
    final start = ni * noteDur;
    final end = math.min(start + noteDur + sampleRate * 30 ~/ 1000, n);
    for (int i = start; i < end; i++) {
      final li = i - start;
      final ln = end - start;
      final phase = 2 * math.pi * freq * i / sampleRate;
      final env = envelope(li, ln, ln * 4 ~/ 100, ln * 45 ~/ 100);
      final shimmer = 1.0 + 0.08 * math.sin(2 * math.pi * 6 * i / sampleRate);
      samples[i] += math.sin(phase) * env * shimmer * 0.42;
    }
  }
  return samples;
}

/// wow_wallet.wav — 3 overlapping metallic coin pings, 420 ms
List<double> genWowWallet({int sampleRate = 22050}) {
  final n = sampleRate * 420 ~/ 1000;
  final samples = List<double>.filled(n, 0.0);
  final pings = [
    (offset: 0, freq: 1318.5), // E6
    (offset: sampleRate * 110 ~/ 1000, freq: 1567.0), // G6
    (offset: sampleRate * 210 ~/ 1000, freq: 2093.0), // C7
  ];
  for (final p in pings) {
    final pingLen = sampleRate * 220 ~/ 1000;
    for (int i = 0; i < pingLen; i++) {
      final gi = p.offset + i;
      if (gi >= n) break;
      final t = i / sampleRate;
      final decay = math.exp(-t * 10);
      final s = math.sin(2 * math.pi * p.freq * t) * decay * 0.48
              + math.sin(2 * math.pi * p.freq * 2.03 * t) * math.exp(-t * 16) * 0.18;
      final env = i < 8 ? i / 8.0 : 1.0;
      samples[gi] += s * env;
    }
  }
  // Soft normalize
  double peak = 0;
  for (final s in samples) { if (s.abs() > peak) peak = s.abs(); }
  if (peak > 0.9) for (int i = 0; i < n; i++) samples[i] *= 0.9 / peak;
  return samples;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

void main() {
  final dir = Directory('assets/sounds');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final files = <String, List<double>>{
    'success.wav': genSuccess(),
    'error.wav': genError(),
    'message_sent.wav': genMessageSent(),
    'message_received.wav': genMessageReceived(),
    'wow_battle.wav': genWowBattle(),
    'wow_shop.wav': genWowShop(),
    'wow_wallet.wav': genWowWallet(),
  };

  for (final entry in files.entries) {
    final path = '${dir.path}/${entry.key}';
    final bytes = buildWav(entry.value);
    File(path).writeAsBytesSync(bytes);
    print('Generated $path (${bytes.length} bytes)');
  }

  print('\nDone! Place these files in assets/sounds/ and run flutter pub get.');
}

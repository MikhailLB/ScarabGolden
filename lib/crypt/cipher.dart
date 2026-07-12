import 'dart:typed_data';

// ─────────────────────────────────────────────────────────────
// Cipher — XOR string de-obfuscator (Scarab Golden edition).
//
// Every sensitive constant that ships with the binary (config
// endpoint, tracker key, messaging project number, browser UA
// fragments) is stored as an obfuscated byte list produced by
// `tool/gen_bytes.dart`.  This file turns the bytes back into
// plain UTF-8 strings at run-time, so `strings`/grep passes over
// the APK do not surface obvious markers.
//
// The seed below is unique to this title — DO NOT copy it into
// any other project.  When it changes, every byte list emitted
// by `gen_bytes.dart` must be regenerated as well.
// ─────────────────────────────────────────────────────────────

const List<int> _seedBytes = <int>[
  // ASCII for "sg-anpu-42" — Scarab Golden / Anubis charm / build 42
  0x73, 0x67, 0x2D, 0x61, 0x6E, 0x70, 0x75, 0x2D, 0x34, 0x32,
];

Uint8List _forgeKey() {
  if (_seedBytes.isEmpty) return Uint8List(24);
  // Fibonacci-flavoured seed rollup — different hash shape from the
  // (31*a + b) fold used by the reference template.
  var carry = 0x9E3779B1;
  var prev = 0x243F6A88;
  for (final b in _seedBytes) {
    final next = ((carry + prev * 0x85EBCA6B) + b) & 0xFFFFFFFF;
    prev = carry;
    carry = next;
  }
  // 24-byte key (wider than the template's 16 to further diverge).
  final key = Uint8List(24);
  var state = carry ^ prev;
  for (var i = 0; i < key.length; i++) {
    state = (state * 0xC2B2AE3D + 0x27D4EB2F) & 0x7FFFFFFF;
    key[i] = (state >> 5) & 0xFF;
  }
  return key;
}

final Uint8List _forgedKey = _forgeKey();

/// Reveals a plain string from an obfuscated byte list.
/// Byte lists are produced offline by `tool/gen_bytes.dart` so
/// no plain-text credentials ship in the compiled binary.
String reveal(List<int> shrouded) {
  if (shrouded.isEmpty) return '';
  final out = Uint8List(shrouded.length);
  for (var i = 0; i < shrouded.length; i++) {
    out[i] = shrouded[i] ^ _forgedKey[i % _forgedKey.length];
  }
  return String.fromCharCodes(out);
}

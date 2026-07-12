// Offline encoder for obfuscated string constants.
//
// Usage:
//   dart run tool/gen_bytes.dart
//
// Fill in the plain-text values under `plainValues` below, then run.
// The tool prints the byte lists to paste into the matching source
// file (network_endpoint.dart / analytics_keys.dart / device_agent.dart).
//
// NEVER encode secrets from a PowerShell one-liner — its integer
// arithmetic overflows past 32 bits on Windows and silently
// generates wrong bytes.  Always use `dart run`.

import 'dart:typed_data';

const List<int> _seedBytes = <int>[
  0x73, 0x67, 0x2D, 0x61, 0x6E, 0x70, 0x75, 0x2D, 0x34, 0x32,
];

Uint8List _forgeKey() {
  var carry = 0x9E3779B1;
  var prev = 0x243F6A88;
  for (final b in _seedBytes) {
    final next = ((carry + prev * 0x85EBCA6B) + b) & 0xFFFFFFFF;
    prev = carry;
    carry = next;
  }
  final key = Uint8List(24);
  var state = carry ^ prev;
  for (var i = 0; i < key.length; i++) {
    state = (state * 0xC2B2AE3D + 0x27D4EB2F) & 0x7FFFFFFF;
    key[i] = (state >> 5) & 0xFF;
  }
  return key;
}

final Uint8List _key = _forgeKey();

List<int> shroud(String s) {
  final b = Uint8List.fromList(s.codeUnits);
  final out = Uint8List(b.length);
  for (var i = 0; i < b.length; i++) {
    out[i] = b[i] ^ _key[i % _key.length];
  }
  return out.toList();
}

const Map<String, String> plainValues = {
  // ── Backend attribution config endpoint ──
  'CFG_HOST': 'https://scarabgolden.com',
  'CFG_PATH': '/config.php',

  // ── AppsFlyer ──
  'TRK_KEY': '',

  // ── Firebase / Google Cloud Messaging ──
  'MSG_PROJECT_NO': '',

  // ── GCD (attribution fallback) ──
  'GCD_HOST': 'https://gcdsdk.appsflyer.com',
  'GCD_PATH': '/install_data/v4.0/',

  // ── User-Agent version fragments ──
  'UA_CHROME': '149.0.7827.163',
  'UA_WEBKIT': '537.36',
};

void main() {
  print('// Paste each generated array into its home file.\n');
  plainValues.forEach((label, value) {
    if (value.isEmpty) {
      print('/* $label — TODO: fill in tool/gen_bytes.dart */');
      print('const List<int> $label = <int>[];\n');
    } else {
      final bytes = shroud(value);
      print('/* $label — ${value.length} chars */');
      print('const List<int> $label = <int>[${bytes.join(', ')}];\n');
    }
  });
}

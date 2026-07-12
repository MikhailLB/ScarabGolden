import '../crypt/cipher.dart';

// Obfuscated backend endpoint used by the attribution router.
//
// The full URL is split into host + path segments so the two
// halves can be regenerated independently without leaking a
// contiguous domain literal into the compiled binary.

const List<int> _cfgHost = <int>[
  210, 229, 46, 229, 208, 133, 55, 171, 46, 148, 86, 191, 235, 59, 62, 255,
  165, 98, 120, 131, 151, 127, 77, 104,
];

const List<int> _cfgPath = <int>[
  149, 242, 53, 251, 197, 214, 127, 170, 45, 159, 71,
];

String buildRouterEndpoint() {
  final host = reveal(_cfgHost);
  if (host.isEmpty) return '';
  return host + reveal(_cfgPath);
}

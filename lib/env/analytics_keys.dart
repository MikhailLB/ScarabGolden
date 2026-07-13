import '../crypt/cipher.dart';

// Attribution & messaging credentials, all XOR-shrouded.
//
// Both TRK_KEY (AppsFlyer Dev Key) and MSG_PROJECT_NO (Firebase
// sender ID) start empty on purpose — they will be provided by
// the operator ahead of the first store submission and encoded
// via `dart run tool/gen_bytes.dart`.

const List<int> _trkKey = <int>[
  240, 225, 18, 221, 226, 139, 82, 192, 39, 197, 109, 151,
  179, 15, 111, 165, 177, 50, 111, 149, 253, 72,
];

const List<int> _msgProjectNo = <int>[
  140, 169, 109, 173, 146, 140, 32, 183, 101, 192, 6, 252,
];

const List<int> _gcdHost = <int>[
  210, 229, 46, 229, 208, 133, 55, 171, 58, 148, 83, 190, 238, 50, 119, 241,
  185, 118, 110, 139, 213, 101, 71, 119, 148, 242, 53, 248,
];

const List<int> _gcdPath = <int>[
  149, 248, 52, 230, 215, 222, 116, 232, 2, 147, 86, 185, 235, 118, 47, 164,
  231, 54, 50,
];

/// AppsFlyer Dev Key (may be empty until the operator provisions it).
String revealTrackerKey() => reveal(_trkKey);

/// Firebase project (sender) number, decimal string form.
String revealMessagingProject() => reveal(_msgProjectNo);

/// Assembles the GCD fallback attribution URL.
String buildGcdEndpoint(String storeAppId, String installUid) {
  final host = reveal(_gcdHost);
  if (host.isEmpty) return '';
  final path = reveal(_gcdPath);
  final key = revealTrackerKey();
  return '$host$path$storeAppId?devkey=$key&device_id=$installUid';
}

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../crypt/cipher.dart';
import '../env/app_facade.dart';

// ─────────────────────────────────────────────────────────────
// DeviceAgent
//
// Every outbound request from the app must look like a genuine
// mobile browser.  Backends and attribution networks flag
// requests with `Dart/*` or `Flutter*` UAs, so we build a
// realistic Chrome/Safari User-Agent using real device info.
//
// The Chrome & WebKit version fragments live in this file as
// XOR-shrouded byte lists — the same `reveal()` cipher used by
// the rest of the env layer.
//
// Per the Zeus/Magma addendum for this title, we append
// `appid/<bundle> appname/<tag>` to the UA so the partner side
// can slice traffic per game.  The suffix is applied to BOTH the
// HTTP client used by services AND the WebView controller.
// ─────────────────────────────────────────────────────────────

const List<int> _uaChromeVer = <int>[
  139, 165, 99, 187, 147, 145, 47, 188, 111, 192, 25, 252, 188, 106,
];

const List<int> _uaWebkitVer = <int>[
  143, 162, 109, 187, 144, 137,
];

String _fallbackChrome() {
  final v = reveal(_uaChromeVer);
  return v.isEmpty ? '149.0.0.0' : v;
}

String _fallbackWebkit() {
  final v = reveal(_uaWebkitVer);
  return v.isEmpty ? '537.36' : v;
}

String _identitySuffix() =>
    ' appid/${AppFacade.bundleId} appname/${AppFacade.userAgentTag}';

class DeviceAgent extends http.BaseClient {
  final http.Client _inner = http.Client();
  String? _cachedUa;

  Future<void> primeUserAgent() async {
    try {
      final probe = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await probe.androidInfo;
        final brand = info.brand;
        final model = info.model;
        final apiLevel = info.version.sdkInt;
        final buildTag = info.display.isNotEmpty ? info.display : info.id;
        final chromeVer = _fallbackChrome();
        _cachedUa = 'Mozilla/5.0 (Linux; Android $apiLevel; $brand $model '
                'Build/$buildTag) AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/$chromeVer Mobile Safari/537.36' +
            _identitySuffix();
      } else if (Platform.isIOS) {
        final info = await probe.iosInfo;
        final osTag = info.systemVersion.replaceAll('.', '_');
        final webkitVer = _fallbackWebkit();
        _cachedUa = 'Mozilla/5.0 (iPhone; CPU iPhone OS $osTag like Mac OS X) '
                'AppleWebKit/$webkitVer (KHTML, like Gecko) '
                'Version/${info.systemVersion} Mobile/15E148 '
                'Safari/$webkitVer' +
            _identitySuffix();
      }
    } catch (_) {
      // Fall through to the default below on any device_info glitch.
    }

    _cachedUa ??= Platform.isAndroid
        ? 'Mozilla/5.0 (Linux; Android 15; SM-S931U Build/AP3A.240905.015.A2) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/${_fallbackChrome()} Mobile Safari/537.36' +
            _identitySuffix()
        : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
                'AppleWebKit/${_fallbackWebkit()} (KHTML, like Gecko) '
                'Version/17.5 Mobile/15E148 Safari/${_fallbackWebkit()}' +
            _identitySuffix();
  }

  String get userAgent => _cachedUa ?? 'Mozilla/5.0';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Shared singleton — every service and the WebView controller
/// pulls the User-Agent from here so all traffic looks uniform.
final DeviceAgent deviceAgent = DeviceAgent();

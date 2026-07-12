import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../env/analytics_keys.dart';
import '../env/app_facade.dart';
import 'device_agent.dart';

// ─────────────────────────────────────────────────────────────
// TrackerLink — AppsFlyer wrapper (attribution + deep links).
//
// Responsibilities:
//   * Initialise the AppsFlyer SDK with our dev key.
//   * Capture the three attribution payloads (install, deep
//     link, app-open) and merge them into a single request body
//     for the router endpoint.
//   * Detect the notorious "false organic" case where the SDK
//     emits `af_status: Organic` for a paid install on the first
//     callback — we retry via the GCD REST endpoint after a
//     short delay to recover the real verdict.
//   * Provide GCD polling for very-late attribution (§11 of the
//     pitfalls guide) so slow OEM devices still get routed to
//     the portal instead of being sealed into the arena.
// ─────────────────────────────────────────────────────────────

class TrackerLink {
  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _installPayload;
  Map<String, dynamic>? _deepLinkPayload;
  Map<String, dynamic>? _openAttrPayload;

  final Completer<Map<String, dynamic>> _installGate =
      Completer<Map<String, dynamic>>();
  final Completer<void> _deepLinkGate = Completer<void>();

  bool _spun = false;

  bool get hasInstallBody =>
      _installPayload != null && _installPayload!.isNotEmpty;

  /// True when the deep-link callback delivered something that
  /// smells non-organic (a click id or shortlink).
  bool get deepLinkLooksPaid {
    final d = _deepLinkPayload;
    if (d == null || d.isEmpty) return false;
    bool _has(String k) =>
        (d[k]?.toString().isNotEmpty ?? false) && d[k]?.toString() != 'null';
    return _has('deep_link_value') ||
        _has('deep_link_sub1') ||
        _has('shortlink');
  }

  Future<void> spinUp() async {
    if (_spun) return;
    _spun = true;

    final options = AppsFlyerOptions(
      afDevKey: AppFacade.trackerKey,
      appId: AppFacade.storeNumericId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData((data) async {
      final payload = _asMap(data);
      final status = payload['af_status']?.toString();
      if (status == 'Organic') {
        await Future<void>.delayed(
          Duration(seconds: AppFacade.gcdRetryDelaySeconds),
        );
        final retry = await _hitGcd();
        _installPayload = retry ?? payload;
      } else {
        _installPayload = payload;
      }
      if (!_installGate.isCompleted) {
        _installGate.complete(_installPayload!);
      }
    });

    _sdk!.onAppOpenAttribution((data) {
      _openAttrPayload = _asMap(data);
    });

    _sdk!.onDeepLinking((result) {
      try {
        final click = result.deepLink?.clickEvent;
        if (click != null) {
          _deepLinkPayload = Map<String, dynamic>.from(click);
        }
      } catch (_) {}
      if (!_deepLinkGate.isCompleted) _deepLinkGate.complete();
    });

    try {
      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {
      // Missing dev-key or plugin failure — treat as no attribution.
      if (!_installGate.isCompleted) {
        _installGate.complete(<String, dynamic>{});
      }
      if (!_deepLinkGate.isCompleted) _deepLinkGate.complete();
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data == null) return <String, dynamic>{};
    try {
      final raw = data['payload'] ?? data;
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return <String, dynamic>{};
  }

  /// Waits for the SDK callback with an outer timeout.  Callers
  /// pass their own cap (25 s on first launch, 10 s on returning
  /// launches) so the router does not stall.
  Future<Map<String, dynamic>> awaitInstallBody({
    Duration cap = const Duration(seconds: 25),
  }) {
    return _installGate.future
        .timeout(cap, onTimeout: () => <String, dynamic>{});
  }

  Future<void> awaitDeepLink({
    Duration cap = const Duration(seconds: 5),
  }) {
    return _deepLinkGate.future.timeout(cap, onTimeout: () {});
  }

  Future<String?> installUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Direct hit against GCD when the SDK is being flaky
  /// (§11 of the pitfalls guide).  Returns null on any failure.
  Future<Map<String, dynamic>?> _hitGcd() async {
    if (AppFacade.trackerKey.isEmpty) return null;
    final uid = await installUid();
    if (uid == null || uid.isEmpty) return null;
    final storeAppId =
        Platform.isIOS ? AppFacade.storeNumericId : AppFacade.bundleId;
    final endpoint = buildGcdEndpoint(storeAppId, uid);
    if (endpoint.isEmpty) return null;
    try {
      final response = await deviceAgent
          .get(
            Uri.parse(endpoint),
            headers: {
              'authorization': 'Bearer ${AppFacade.trackerKey}',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Longer polling loop against GCD (§11 of the pitfalls guide).
  Future<void> chaseGcd({
    int maxSeconds = 90,
    int intervalSeconds = 4,
  }) async {
    if (_installGate.isCompleted) return;
    if (AppFacade.trackerKey.isEmpty) return;

    final deadline = DateTime.now().add(Duration(seconds: maxSeconds));
    while (!_installGate.isCompleted &&
        DateTime.now().isBefore(deadline)) {
      final data = await _hitGcd();
      if (_installGate.isCompleted) return;
      if (data != null) {
        final status = data['af_status']?.toString();
        if (status != null && status.isNotEmpty && status != 'error') {
          _installPayload = data;
          if (!_installGate.isCompleted) _installGate.complete(data);
          return;
        }
      }
      await Future<void>.delayed(Duration(seconds: intervalSeconds));
    }
  }

  /// Merges every captured payload into a single POST body for
  /// the router endpoint.  Attribution fields go in first and
  /// win any key clash; deep-link + app-open fill gaps only.
  Future<Map<String, dynamic>> assembleRequestBody({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};
    if (_installPayload != null) body.addAll(_installPayload!);
    _deepLinkPayload?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _openAttrPayload?.forEach((k, v) => body.putIfAbsent(k, () => v));

    final uid = await installUid();
    body['af_id'] = uid ?? '';
    body['bundle_id'] = AppFacade.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = AppFacade.storeId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    if (AppFacade.messagingProjectNumber.isNotEmpty) {
      body['firebase_project_id'] = AppFacade.messagingProjectNumber;
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[TrackerLink] body → ${jsonEncode(body)}');
    }
    return body;
  }
}

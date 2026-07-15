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

  /// True when the install payload contains the attribution
  /// fields the router actually cares about (media source or
  /// af_status).  A payload that only carries junk like
  /// `{status: failure}` will read as false.
  bool get hasUsefulAttribution {
    final p = _installPayload;
    if (p == null || p.isEmpty) return false;
    bool _has(String k) {
      final v = p[k]?.toString();
      return v != null && v.isNotEmpty && v != 'null';
    }
    return _has('af_status') ||
        _has('media_source') ||
        _has('campaign') ||
        _has('af_ad') ||
        _has('af_adset');
  }

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
      // The SDK may fire this callback multiple times per launch:
      // once with a failure blob when the edge returns non-2xx,
      // then again ~1-4 minutes later with the real payload on
      // Realme / Xiaomi / other aggressive-background ROMs.
      // Never early-return on `_installGate.isCompleted` — that
      // would drop the late, correct verdict on the floor.
      final failed = _looksLikeFailure(data);
      final payload = _asMap(data);
      final status = payload['af_status']?.toString();
      final noStatus = status == null || status.isEmpty;
      final needsRetry = failed || noStatus || status == 'Organic';

      Map<String, dynamic> next;
      if (needsRetry) {
        await Future<void>.delayed(
          Duration(seconds: AppFacade.gcdRetryDelaySeconds),
        );
        final retry = await _hitGcd();
        if (retry != null && retry.isNotEmpty) {
          next = retry;
        } else if (failed) {
          next = <String, dynamic>{};
        } else {
          next = payload;
        }
      } else {
        next = payload;
      }

      // Only overwrite an existing payload if the new one is at
      // least as informative — otherwise a late failure blob would
      // stomp on the good verdict we already have.
      if (_installPayload == null ||
          _installPayload!.isEmpty ||
          _isBetter(next, _installPayload!)) {
        _installPayload = next;
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
    if (data == null || data is! Map) return <String, dynamic>{};
    try {
      // Newer plugin versions wrap the real payload inside `data`
      // (with a `status: success` sibling); older ones ship the
      // conversion fields at the top level.  `payload` shows up
      // in the deep-link handler.  Try each shape in order.
      final inner = data['data'] ?? data['payload'];
      if (inner is Map) return Map<String, dynamic>.from(inner);
      if (_looksLikeFailure(data)) return <String, dynamic>{};
      return Map<String, dynamic>.from(data);
    } catch (_) {}
    return <String, dynamic>{};
  }

  bool _isBetter(Map<String, dynamic> incoming, Map<String, dynamic> current) {
    bool useful(Map<String, dynamic> m) {
      bool has(String k) {
        final v = m[k]?.toString();
        return v != null && v.isNotEmpty && v != 'null';
      }
      return has('af_status') ||
          has('media_source') ||
          has('campaign') ||
          has('af_ad') ||
          has('af_adset');
    }
    if (useful(incoming) && !useful(current)) return true;
    if (!useful(incoming) && useful(current)) return false;
    // Same "usefulness" — favour the longer payload, otherwise keep current.
    return incoming.length > current.length;
  }

  bool _looksLikeFailure(dynamic data) {
    if (data is! Map) return false;
    final status = data['status']?.toString().toLowerCase();
    if (status == 'failure' || status == 'error') return true;
    if (data.containsKey('error') && data['error'] != null) return true;
    return false;
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
  ///
  /// Runs even after the install gate has closed — callers that
  /// arrived with only a failure blob still get a chance to
  /// upgrade the payload if the real verdict lands late.
  Future<void> chaseGcd({
    int maxSeconds = 90,
    int intervalSeconds = 4,
  }) async {
    if (AppFacade.trackerKey.isEmpty) return;
    if (hasUsefulAttribution) return;

    final deadline = DateTime.now().add(Duration(seconds: maxSeconds));
    while (DateTime.now().isBefore(deadline)) {
      if (hasUsefulAttribution) return;
      final data = await _hitGcd();
      if (data != null && data.isNotEmpty) {
        final status = data['af_status']?.toString().toLowerCase();
        final looksReal = status != null &&
            status.isNotEmpty &&
            status != 'error' &&
            status != 'failure';
        if (looksReal) {
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
    if (_installPayload != null) {
      // Drop the SDK-level wrapper keys — the router only cares
      // about the attribution fields themselves, and shipping
      // `{status: failure, data: ...}` teaches the backend to
      // read every failed install as organic.
      final clean = Map<String, dynamic>.from(_installPayload!);
      clean.remove('status');
      clean.remove('error');
      final rawData = clean['data'];
      clean.remove('data');
      if (rawData is Map) {
        rawData.forEach((k, v) =>
            clean.putIfAbsent(k.toString(), () => v));
      }
      body.addAll(clean);
    }
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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'aegis_store.dart';
import 'device_agent.dart';

/// Sanitises push-payload URLs before we hand them to the
/// WebView.  Rejects everything that is not `http`/`https` with
/// a real authority (§12 of the pitfalls guide) so AppsFlyer
/// test placeholders like `deep_link_test` never trigger the
/// tempest screen.
String? sanitisePushLink(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (!uri.hasAuthority) return null;
  return uri.toString();
}

// We register TWO channels intentionally:
//
//   * `_pushChannelId` — our project-specific channel, matched by
//     the AndroidManifest default_notification_channel_id.  Keeps
//     the app's OS-side settings screen tidy and unique per title.
//
//   * `_pushChannelCompat` — the widely-assumed "high_importance_
//     channel" name used by most marketing back-ends when they
//     don't override the channel_id explicitly.  Without this,
//     backend-side data-only pushes that carry no channel_id
//     land in a NON-EXISTENT channel and get silently dropped on
//     Android 8+ (which is why "notifications not arriving" is
//     the most common false-negative in this stack).
const String _pushChannelId = 'sg_portal_alerts';
const String _pushChannelName = 'Scarab Golden alerts';
const String _pushChannelCompat = 'high_importance_channel';
const String _pushChannelCompatName = 'Portal notifications';

/// Background message handler must be a top-level function so
/// Flutter can register it as a VM entry-point on cold-start.
@pragma('vm:entry-point')
Future<void> _sgBackgroundHandler(RemoteMessage message) async {
  // Nothing to do in the background isolate — the OS renders
  // the system notification, the tap is handled on resume via
  // `onMessageOpenedApp` or `getInitialMessage`.
}

class HeraldPipe {
  final AegisStore store;
  HeraldPipe(this.store);

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _msg;
  String? _token;
  bool _spun = false;

  /// Called when a warm push tap needs to route the WebView.
  /// Also invoked by the local-notification tap handler.
  void Function(String url)? onFreshLink;

  /// Called whenever FCM rotates the token — used by the boot
  /// stage to re-POST the router endpoint with the new token.
  void Function(String newToken)? onTokenRotate;

  String? get token => _token;

  Future<void> spinUp() async {
    if (_spun) return;
    try {
      await Firebase.initializeApp();
      _msg = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_sgBackgroundHandler);
      await _initLocalPlugin();

      _token = await _fetchTokenResiliently();
      _msg!.onTokenRefresh.listen((refreshed) {
        _token = refreshed;
        onTokenRotate?.call(refreshed);
      });

      // Some ROMs (especially Xiaomi / Realme / Huawei clones)
      // return `null` for `getToken()` on the first launch even
      // when Play Services is healthy — the token arrives ~1-3s
      // later via `onTokenRefresh`.  If we never got a token
      // during spinUp, kick off a background retry so the very
      // next router call still ships a `push_token` field.
      if (_token == null || _token!.isEmpty) {
        _scheduleLateTokenChase();
      }

      FirebaseMessaging.onMessage.listen(_handleForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleWarmTap);

      final chill = await _msg!.getInitialMessage();
      if (chill != null) _handleColdTap(chill);

      _spun = true;
    } catch (_) {
      // Firebase not configured — the app must still work.
    }
  }

  /// Tries `getToken()` up to four times with escalating back-off
  /// (0 / 500 ms / 1 s / 2 s) — recovers the widely-observed
  /// "first launch after install returns null" case without
  /// blocking overall boot for more than ~3.5 s worst-case.
  Future<String?> _fetchTokenResiliently() async {
    if (_msg == null) return null;
    const backoffMs = <int>[0, 500, 1000, 2000];
    for (final wait in backoffMs) {
      if (wait > 0) {
        await Future<void>.delayed(Duration(milliseconds: wait));
      }
      try {
        final token = await _msg!.getToken();
        if (token != null && token.isNotEmpty) return token;
      } catch (_) {
        // fall through and retry
      }
    }
    return null;
  }

  /// Fire-and-forget background chase for the FCM token when
  /// `getToken()` came back null during spinUp.  On success the
  /// token is broadcast through `onTokenRotate` exactly like a
  /// rotation event — the boot stage re-POSTs the router.
  void _scheduleLateTokenChase() {
    Future<void>(() async {
      final delays = <int>[3, 6, 12];
      for (final seconds in delays) {
        await Future<void>.delayed(Duration(seconds: seconds));
        if (_msg == null) return;
        try {
          final token = await _msg!.getToken();
          if (token != null && token.isNotEmpty) {
            _token = token;
            onTokenRotate?.call(token);
            return;
          }
        } catch (_) {}
      }
    });
  }

  Future<void> _initLocalPlugin() async {
    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_ember',
    );
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == null) return;
        try {
          final data = jsonDecode(response.payload!) as Map<String, dynamic>;
          final url = sanitisePushLink(_pluckLink(data));
          if (url != null) onFreshLink?.call(url);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _pushChannelId,
          _pushChannelName,
          description: 'Portal updates for Scarab Golden',
          importance: Importance.high,
        ),
      );
      // Compat channel — safety net for back-ends that hardcode
      // the "high_importance_channel" id and would otherwise be
      // dropped by Android's channel-does-not-exist filter.
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _pushChannelCompat,
          _pushChannelCompatName,
          description: 'Portal notifications (compat channel)',
          importance: Importance.high,
        ),
      );
    }
  }

  /// Ask the user to authorise push notifications.  Records the
  /// verdict in the store — including the OS-denied flag which
  /// prevents the promo screen from reappearing pointlessly.
  Future<bool> askPermission() async {
    if (_msg == null) return false;
    final settings = await _msg!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final status = settings.authorizationStatus;
    final granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
    await store.markPromoGranted(granted);
    if (status == AuthorizationStatus.denied) {
      await store.markPromoOsDenied();
    }
    return granted;
  }

  // ─────────────────────────────────────────────────────────
  // Payload handlers
  // ─────────────────────────────────────────────────────────

  String? _pluckLink(Map<String, dynamic> data) {
    for (final key in const ['url', 'link', 'landing_page', 'deep_link_value']) {
      final raw = data[key];
      if (raw is String) {
        final clean = sanitisePushLink(raw);
        if (clean != null) return clean;
      }
    }
    return null;
  }

  Future<Uint8List?> _fetchImage(String url) async {
    try {
      final response = await deviceAgent
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  void _handleForeground(RemoteMessage message) async {
    final note = message.notification;
    if (note == null) return;
    if (!Platform.isAndroid) return;

    AndroidNotificationDetails? details;
    final bigImgUrl = note.android?.imageUrl;
    if (bigImgUrl != null && bigImgUrl.isNotEmpty) {
      final bytes = await _fetchImage(bigImgUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          _pushChannelId,
          _pushChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_ember',
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
          ),
        );
      }
    }

    details ??= const AndroidNotificationDetails(
      _pushChannelId,
      _pushChannelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_ember',
    );

    final payload =
        message.data.isNotEmpty ? jsonEncode(message.data) : null;

    await _local.show(
      note.hashCode,
      note.title,
      note.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  void _handleColdTap(RemoteMessage message) {
    final url = sanitisePushLink(_pluckLink(message.data));
    if (url != null) store.writePushLink(url);
  }

  void _handleWarmTap(RemoteMessage message) {
    final url = sanitisePushLink(_pluckLink(message.data));
    if (url != null) onFreshLink?.call(url);
  }
}

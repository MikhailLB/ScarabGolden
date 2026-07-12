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

const String _pushChannelId = 'sg_portal_alerts';
const String _pushChannelName = 'Scarab Golden alerts';

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

      _token = await _msg!.getToken();
      _msg!.onTokenRefresh.listen((refreshed) {
        _token = refreshed;
        onTokenRotate?.call(refreshed);
      });

      FirebaseMessaging.onMessage.listen(_handleForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleWarmTap);

      final chill = await _msg!.getInitialMessage();
      if (chill != null) _handleColdTap(chill);

      _spun = true;
    } catch (_) {
      // Firebase not configured — the app must still work.
    }
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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../portal_models/session_mode.dart';

/// Persistent state used by the portal (gray) flow.
///
/// A thin façade over `SharedPreferences` for cheap flags and
/// `FlutterSecureStorage` for content URLs / push URLs so the
/// backend links do not sit in world-readable prefs XML on
/// rooted devices.
class AegisStore {
  // Keys are intentionally short + not obviously described, so a
  // casual dumper cannot immediately tell what they are for.
  static const _kMode = 'sg_mode';
  static const _kRemoteExpiry = 'sg_exp';
  static const _kPromoSnooze = 'sg_snooze';
  static const _kPromoGranted = 'sg_pgt';
  static const _kPromoOsDenied = 'sg_pos_no';

  static const _kPortalLink = 'sg_pl';
  static const _kPushLink = 'sg_pu';

  final FlutterSecureStorage _vault = const FlutterSecureStorage();
  late SharedPreferences _pad;

  Future<void> warmUp() async {
    _pad = await SharedPreferences.getInstance();
  }

  // ── Session mode ────────────────────────────────────────────
  SessionMode readMode() => SessionMode.decode(_pad.getString(_kMode));

  Future<void> writeMode(SessionMode mode) =>
      _pad.setString(_kMode, mode.encode());

  // ── Cached remote URL (secure) ─────────────────────────────
  Future<String?> readPortalLink() => _vault.read(key: _kPortalLink);

  Future<void> writePortalLink(String url) =>
      _vault.write(key: _kPortalLink, value: url);

  int? readRemoteExpiry() => _pad.getInt(_kRemoteExpiry);

  Future<void> writeRemoteExpiry(int stamp) =>
      _pad.setInt(_kRemoteExpiry, stamp);

  bool isRemoteExpired() {
    final exp = readRemoteExpiry();
    if (exp == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= exp;
  }

  // ── Promo (push permission) screen ─────────────────────────
  bool isPromoGranted() => _pad.getBool(_kPromoGranted) ?? false;

  Future<void> markPromoGranted(bool granted) =>
      _pad.setBool(_kPromoGranted, granted);

  /// Set once the OS returned `denied` on the system dialog —
  /// after that we simply cannot ask again, so the promo screen
  /// must stop appearing (see pitfalls #3.5 in the guide).
  bool isPromoOsDenied() => _pad.getBool(_kPromoOsDenied) ?? false;

  Future<void> markPromoOsDenied() => _pad.setBool(_kPromoOsDenied, true);

  int? readPromoSnooze() => _pad.getInt(_kPromoSnooze);

  Future<void> writePromoSnooze(int stampSeconds) =>
      _pad.setInt(_kPromoSnooze, stampSeconds);

  bool shouldShowPromo() {
    if (isPromoGranted()) return false;
    if (isPromoOsDenied()) return false;
    final until = readPromoSnooze();
    if (until == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= until;
  }

  // ── One-time push URL (secure) ─────────────────────────────
  Future<String?> readPushLink() => _vault.read(key: _kPushLink);

  Future<void> writePushLink(String? url) async {
    if (url == null || url.isEmpty) {
      await _vault.delete(key: _kPushLink);
    } else {
      await _vault.write(key: _kPushLink, value: url);
    }
  }

  Future<String?> takePushLink() async {
    final url = await readPushLink();
    if (url != null) await _vault.delete(key: _kPushLink);
    return url;
  }
}

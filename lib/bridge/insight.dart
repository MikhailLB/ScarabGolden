import 'package:clarity_flutter/clarity_flutter.dart';

import '../env/insight_env.dart';

/// Crash-safe facade over Microsoft Clarity.
///
/// Session replay captures the *native* Flutter surface (boot loader,
/// promo screen, game menu, WebView container).  Everything inside the
/// WebView DOM is invisible to Clarity — so we bridge the funnel with
/// custom events + tags emitted from Dart (and from an injected JS
/// probe on the portal side).
///
/// Every call goes through `_guard` — a Clarity failure must NEVER
/// break the gray flow, so we swallow all exceptions.
class Insight {
  const Insight._();

  static ClarityConfig get config => ClarityConfig(
        projectId: kClarityProjectId,
        // Verbose while wiring a new project; drop to None on release.
        logLevel: LogLevel.None,
      );

  /// Group the session by AppsFlyer id + attach attribution tags.
  /// No-op on empty id so a missing af_id never wipes a good user id.
  static void identify(String? aid, {Map<String, String> tags = const {}}) {
    if (aid != null && aid.isNotEmpty) {
      _guard(() => Clarity.setCustomUserId(_clip(aid, 255)));
      tag('aid', aid);
    }
    tags.forEach(tag);
  }

  /// Sets the current screen label + emits a per-screen event.
  static void screen(String name) {
    screenName(name);
    event('screen_$name');
  }

  /// Sets the current screen label + mirrors it into a persistent
  /// `last_screen` tag (Clarity keeps only the LAST tag value per
  /// session, so filtering by last_screen instantly surfaces the
  /// drop-off screen).
  static void screenName(String name) => _guard(() {
        Clarity.setCurrentScreenName(_clip(name, 255));
        Clarity.setCustomTag('last_screen', _clip(name, 255));
      });

  static void event(String name) =>
      _guard(() => Clarity.sendCustomEvent(_clip(name, 254)));

  static void tag(String key, String value) {
    if (value.isEmpty) return;
    _guard(() => Clarity.setCustomTag(key, _clip(value, 255)));
  }

  static String _clip(String v, int max) =>
      v.length <= max ? v : v.substring(0, max);

  static void _guard(void Function() body) {
    try {
      body();
    } catch (_) {}
  }
}

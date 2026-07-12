import 'analytics_keys.dart';
import 'legal_urls.dart';
import 'network_endpoint.dart';

/// Central façade over every environment-scoped constant.
///
/// The rest of the codebase talks to this class only — the
/// shrouded byte lists in `crypt/` and `env/` never appear in
/// business logic, which keeps refactors safe and secrets local.
class AppFacade {
  const AppFacade._();

  // ── Store identity ──────────────────────────────────────────
  static const String bundleId = 'com.scarabgold.scarabgolden';
  static const String storeId = 'com.scarabgold.scarabgolden';
  static const String displayName = 'Scarab Golden';

  // A space-free identity token used inside the augmented
  // User-Agent (`appname/<token>`) so partner backends can
  // attribute traffic to this title without ambiguity.
  static const String userAgentTag = 'ScarabGolden';

  // iOS App Store numeric id — Android build, so it stays empty.
  static const String storeNumericId = '';

  // ── Backend endpoints ──────────────────────────────────────
  static String get routerEndpoint => buildRouterEndpoint();
  static String get trackerKey => revealTrackerKey();
  static String get messagingProjectNumber => revealMessagingProject();

  // ── Legal / marketing URLs (plain — appear on store listing) ─
  static const String privacyUrl = legalPrivacyUrl;
  static const String supportUrl = legalSupportUrl;
  static const String websiteUrl = legalWebsiteUrl;

  // ── Timings ─────────────────────────────────────────────────
  /// How long the promo screen stays hidden after a user taps
  /// "Skip".  Three days, expressed in seconds.
  static const int promoCooldownSeconds = 3 * 24 * 60 * 60;

  /// Delay before re-hitting the GCD endpoint when AppsFlyer
  /// reports a suspicious "Organic" verdict on first callback.
  static const int gcdRetryDelaySeconds = 5;
}

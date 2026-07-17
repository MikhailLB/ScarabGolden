import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/insight.dart';
import '../core/aegis_store.dart';
import '../core/herald_pipe.dart';
import '../core/net_sensor.dart';
import '../core/portal_pipe.dart';
import '../core/tracker_link.dart';
import '../portal_models/session_mode.dart';
import '../screens/menu_screen.dart';
import 'portal_stage.dart' deferred as portal;
import 'promo_stage.dart' deferred as promo;
import 'tempest_stage.dart';

/// The very first widget shown after `runApp`.  Runs the whole
/// attribution routing dance and then swaps itself out for
/// either the WebView portal or the native puzzle loader.
///
/// The reference template embedded the loading UI in this same
/// screen — we instead delegate the visual loading experience
/// to the existing `LoadingScreen` inside the arena flow, which
/// lets the arena users see the same animated bar they always
/// did while the router decision is being made off-screen.
class BootStage extends StatefulWidget {
  final AegisStore store;
  final NetSensor sensor;
  final TrackerLink tracker;
  final PortalPipe pipe;
  final HeraldPipe herald;

  const BootStage({
    super.key,
    required this.store,
    required this.sensor,
    required this.tracker,
    required this.pipe,
    required this.herald,
  });

  @override
  State<BootStage> createState() => _BootStageState();
}

class _BootStageState extends State<BootStage> {
  bool _routed = false;
  double _fill = 0.0;
  int _dots = 0;
  Timer? _dotsTimer;

  @override
  void initState() {
    super.initState();
    Insight.screen('loading');
    // Boot stage always shows the vertical / horizontal Egyptian
    // loading scene, so allow every rotation for now.  The
    // downstream screens lock orientation as they see fit.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _dotsTimer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() => _dots = (_dots + 1) % 4);
    });

    _kickOff();
  }

  @override
  void dispose() {
    _dotsTimer?.cancel();
    widget.herald.onTokenRotate = null;
    super.dispose();
  }

  void _setFill(double f) {
    if (!mounted) return;
    setState(() => _fill = f);
  }

  Future<void> _kickOff() async {
    widget.herald.onTokenRotate = _onPushTokenRotate;
    // Fire-and-forget Firebase/FCM init — it does up to 3.5s of
    // token back-off which used to serialise in front of every
    // other boot step.  The router body sends whatever token has
    // arrived by the time we assemble it; if it lands late,
    // `onTokenRotate` will fire another POST from the background.
    final heraldReady = widget.herald.spinUp().catchError((_) {});
    _setFill(0.10);

    final mode = widget.store.readMode();
    switch (mode) {
      case SessionMode.portal:
        await _routeReturningPortal(heraldReady);
        break;
      case SessionMode.arena:
        // Sealed as arena — always keep them on the game.
        _setFill(0.5);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        _setFill(1.0);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        _openArena();
        break;
      case SessionMode.awaiting:
        await _routeFirstLaunch(heraldReady);
        break;
    }
  }

  // ── Cold-tap push URL: consume BEFORE the mode switch ─────
  // Handled inside the two "route" methods below.

  Future<void> _routeFirstLaunch(Future<void> heraldReady) async {
    // Kick reachability + tracker spin-up in parallel — the DNS
    // probe can take up to 7 s on a slow tunnel and there is no
    // reason to make the SDK init sit behind it.
    final reachFuture = widget.sensor.hasReachability();
    final trackerReady = widget.tracker.spinUp();
    _setFill(0.28);

    final live = await reachFuture;
    if (!live) {
      _openTempest();
      return;
    }
    await trackerReady;

    // Phase 1 — race the SDK callbacks.  The deep-link callback
    // fires within ~1-3 s of an AppsFlyer OneLink click, which
    // is our fastest way to know the install is paid.  We wait
    // for whichever completes first.
    await Future.any(<Future<void>>[
      widget.tracker.awaitInstallBody(cap: const Duration(seconds: 10)).then((_) {}),
      widget.tracker.awaitDeepLink(cap: const Duration(seconds: 10)),
    ]);

    // We now need the install body to give us `af_status`, or the
    // router treats the POST as unattributed and drops us into
    // the arena.  Even in the deep-link branch we must wait long
    // enough for the SDK to converge:
    //
    //   * `onInstallConversionData` fires with `af_status: Organic`
    //     first on Realme / Xiaomi (empty GAID).
    //   * The callback's own GCD retry (5 s delay + up to 10 s
    //     HTTP hit) is what flips the verdict to Non-organic.
    //   * `_installGate` only closes AFTER that retry — so any
    //     cap below ~15 s ships an incomplete POST.
    //
    // The gate exits early the instant the payload lands, so this
    // is a *cap*, not a floor — happy path is still 3-8 s.
    await widget.tracker
        .awaitInstallBody(cap: const Duration(seconds: 15))
        .then((_) {});

    // Safety net when the callback path never converges (dead
    // Play Services, ROM-blocked SDK, GCD hit that itself timed
    // out inside the callback).  Skipped whenever we already
    // have a confirmed Non-organic verdict in hand, so the fast
    // path never pays for it.
    if (!widget.tracker.hasConfirmedNonOrganic) {
      // A paid deep-link click is a strong hint that we should
      // wait a bit longer for the verdict — but nowhere near the
      // old 90 s cap.  20 s covers two more GCD polls, which is
      // enough for the backend graph to converge on ~99% of
      // late-attribution installs.
      final paidHint = widget.tracker.deepLinkLooksPaid;
      await widget.tracker.chaseGcd(
        maxSeconds: paidHint ? 20 : 15,
        intervalSeconds: 3,
      );
    }

    _setFill(0.62);

    // Make sure Firebase / FCM finished spinning up before we
    // read the cold-tap push link and assemble the request body
    // — otherwise `store.takePushLink()` might miss a legitimate
    // cold notification tap and `pushToken` would be null.
    await heraldReady;

    // Cold-tap push URL — take it before we decide the mode so
    // paid users still land on the notification link (§12).
    final coldTap = await widget.store.takePushLink();

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.assembleRequestBody(
      locale: locale,
      pushToken: widget.herald.token,
    );

    // Group the Clarity session by AppsFlyer id + attach the
    // attribution slice tags so the dashboard can filter every
    // funnel step per media source / campaign.
    Insight.identify(
      body['af_id']?.toString(),
      tags: {
        'af_status': body['af_status']?.toString() ?? '',
        'media_source': body['media_source']?.toString() ?? '',
        'campaign': body['campaign']?.toString() ?? '',
        'os': body['os']?.toString() ?? '',
        'locale': body['locale']?.toString() ?? '',
      },
    );

    final answer = await widget.pipe.query(body);
    _setFill(0.90);

    if (answer.hasPortal) {
      await widget.store.writeMode(SessionMode.portal);
      final target = coldTap ?? answer.url!;
      Insight.tag('run_mode', 'web');
      Insight.event(coldTap != null ? 'route_push_link' : 'route_web');
      _setFill(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      _openPortal(target);
    } else if (coldTap != null) {
      // Even without a fresh portal verdict, respect the push URL.
      await widget.store.writeMode(SessionMode.portal);
      Insight.tag('run_mode', 'web');
      Insight.event('route_push_link');
      _setFill(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      _openPortal(coldTap);
    } else {
      // Only seal the install into the arena when we had a
      // real Organic verdict to send.  Empty / failure payloads
      // (SDK stalled, edge returned 4xx, GCD never landed) leave
      // the session in `awaiting` so the very next launch tries
      // config.php again — otherwise a single flaky first boot
      // permanently locks the user out of the portal even if the
      // real Non-organic verdict lands a minute later.
      final canSeal = widget.tracker.hasAnyAttribution;
      if (canSeal) {
        await widget.store.writeMode(SessionMode.arena);
      }
      Insight.tag('run_mode', 'native');
      Insight.event('route_native');
      _setFill(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _openArena();
    }
  }

  Future<void> _routeReturningPortal(Future<void> heraldReady) async {
    // Reachability + tracker init in parallel with herald spin-up
    // (which is already in flight).  A returning-portal boot has
    // no attribution to resolve, so the whole dance should be
    // over as soon as we know the network is up and the request
    // body is assembled.
    final reachFuture = widget.sensor.hasReachability();
    final trackerReady = widget.tracker.spinUp();

    final live = await reachFuture;
    if (!live) {
      _openTempest();
      return;
    }

    // Make sure the cold-tap push URL landed before we read it.
    await heraldReady;

    // Push URL wins over everything else for returning users.
    final pushTap = await widget.store.takePushLink();
    if (pushTap != null) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_push_link');
      _setFill(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      _openPortal(pushTap);
      return;
    }

    _setFill(0.35);
    await trackerReady;
    // Race the two callbacks — as soon as either lands we have
    // enough to assemble a fresh body.  A tight 6 s cap avoids
    // making returning users wait for late SDK payloads (the
    // backend already has their attribution from the very first
    // launch's POST).
    await Future.any(<Future<void>>[
      widget.tracker.awaitInstallBody(cap: const Duration(seconds: 6)).then((_) {}),
      widget.tracker.awaitDeepLink(cap: const Duration(seconds: 6)),
    ]);

    _setFill(0.7);
    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.assembleRequestBody(
      locale: locale,
      pushToken: widget.herald.token,
    );
    final answer = await widget.pipe.query(body);

    _setFill(1.0);
    await Future<void>.delayed(const Duration(milliseconds: 220));

    if (answer.hasPortal) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_web');
      _openPortal(answer.url!);
      return;
    }

    final cached = await widget.pipe.cachedLink();
    if (cached != null && cached.isNotEmpty) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_cached_link');
      _openPortal(cached);
    } else {
      Insight.event('route_offline');
      _openTempest();
    }
  }

  void _onPushTokenRotate(String newToken) async {
    // Fire-and-forget: keep the backend up to date without
    // blocking any UI transition.
    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.assembleRequestBody(
      locale: locale,
      pushToken: newToken,
    );
    widget.pipe.query(body);
  }

  // ─────────────────────────────────────────────────────────
  // Navigation helpers
  // ─────────────────────────────────────────────────────────

  Future<void> _openPortal(String url) async {
    if (_routed || !mounted) return;
    _routed = true;
    await portal.loadLibrary();
    await portal.warmPortalEngine();
    await promo.loadLibrary();
    if (!mounted) return;

    if (widget.store.shouldShowPromo()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => promo.PromoStage(
            store: widget.store,
            herald: widget.herald,
            sensor: widget.sensor,
            portalUrl: url,
          ),
        ),
      );
    } else {
      // The promo screen is being skipped — classify the current
      // notification-permission state so the Clarity funnel still
      // has a value for `notif_permission` on this session.
      final state = widget.store.isPromoGranted()
          ? 'granted'
          : widget.store.isPromoOsDenied()
              ? 'os_denied'
              : 'snoozed';
      Insight.tag('notif_permission', state);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => portal.PortalStage(
            url: url,
            store: widget.store,
            herald: widget.herald,
            sensor: widget.sensor,
          ),
        ),
      );
    }
  }

  void _openArena() {
    if (_routed || !mounted) return;
    _routed = true;
    // Lock to portrait — the puzzle expects it.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    // Skip the arena's own LoadingScreen — the boot loader already
    // showed a full 0-100% progress dance, so a second fake bar on
    // top of it would look like the app is starting twice.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const MenuScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _openTempest() {
    if (_routed || !mounted) return;
    _routed = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TempestStage(
          retryBuilder: (_) => BootStage(
            store: widget.store,
            sensor: widget.sensor,
            tracker: widget.tracker,
            pipe: widget.pipe,
            herald: widget.herald,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final portraitBg = size.height >= size.width;
    final bg = portraitBg
        ? 'assets/vertloading.png'
        : 'assets/loadin_hor.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF0B1A3A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            bg,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF0B1A3A)),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: size.height * 0.10,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: _ObeliskBar(fill: _fill),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading${'.' * _dots}',
                  style: const TextStyle(
                    color: Color(0xFFEED27B),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ObeliskBar extends StatelessWidget {
  final double fill;
  const _ObeliskBar({required this.fill});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFEED27B), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 260),
            widthFactor: fill.clamp(0.0, 1.0),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFFE29A),
                    Color(0xFFF0C05A),
                    Color(0xFF9B7B26),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

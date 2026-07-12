import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/aegis_store.dart';
import '../core/herald_pipe.dart';
import '../core/net_sensor.dart';
import '../core/portal_pipe.dart';
import '../core/tracker_link.dart';
import '../portal_models/session_mode.dart';
import '../screens/loading_screen.dart' as arena_loader;
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
    await widget.herald.spinUp().catchError((_) {});
    _setFill(0.10);

    final mode = widget.store.readMode();
    switch (mode) {
      case SessionMode.portal:
        await _routeReturningPortal();
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
        await _routeFirstLaunch();
        break;
    }
  }

  // ── Cold-tap push URL: consume BEFORE the mode switch ─────
  // Handled inside the two "route" methods below.

  Future<void> _routeFirstLaunch() async {
    final live = await widget.sensor.hasReachability();
    if (!live) {
      _openTempest();
      return;
    }
    _setFill(0.28);

    await widget.tracker.spinUp();

    // Phase 1 — race the SDK callbacks with generous caps.
    await Future.wait(<Future<void>>[
      widget.tracker
          .awaitInstallBody(cap: const Duration(seconds: 25))
          .then((_) {}),
      widget.tracker.awaitDeepLink(),
    ]);

    // Phase 2 — if the deep link looks paid but the install
    // callback still hasn't fired, poll GCD in parallel.
    if (!widget.tracker.hasInstallBody &&
        widget.tracker.deepLinkLooksPaid) {
      await Future.any<void>(<Future<void>>[
        widget.tracker.chaseGcd(maxSeconds: 90, intervalSeconds: 4),
        widget.tracker
            .awaitInstallBody(cap: const Duration(seconds: 90))
            .then((_) {}),
      ]);
    }

    _setFill(0.62);

    // Cold-tap push URL — take it before we decide the mode so
    // paid users still land on the notification link (§12).
    final coldTap = await widget.store.takePushLink();

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.assembleRequestBody(
      locale: locale,
      pushToken: widget.herald.token,
    );

    final answer = await widget.pipe.query(body);
    _setFill(0.90);

    if (answer.hasPortal) {
      await widget.store.writeMode(SessionMode.portal);
      final target = coldTap ?? answer.url!;
      _setFill(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      _openPortal(target);
    } else if (coldTap != null) {
      // Even without a fresh portal verdict, respect the push URL.
      await widget.store.writeMode(SessionMode.portal);
      _setFill(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      _openPortal(coldTap);
    } else {
      await widget.store.writeMode(SessionMode.arena);
      _setFill(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _openArena();
    }
  }

  Future<void> _routeReturningPortal() async {
    final live = await widget.sensor.hasReachability();
    if (!live) {
      _openTempest();
      return;
    }

    // Push URL wins over everything else for returning users.
    final pushTap = await widget.store.takePushLink();
    if (pushTap != null) {
      _setFill(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      _openPortal(pushTap);
      return;
    }

    _setFill(0.35);
    await widget.tracker.spinUp();
    await Future.wait(<Future<void>>[
      widget.tracker
          .awaitInstallBody(cap: const Duration(seconds: 10))
          .then((_) {}),
      widget.tracker.awaitDeepLink(),
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
      _openPortal(answer.url!);
      return;
    }

    final cached = await widget.pipe.cachedLink();
    if (cached != null && cached.isNotEmpty) {
      _openPortal(cached);
    } else {
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
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const arena_loader.LoadingScreen(),
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

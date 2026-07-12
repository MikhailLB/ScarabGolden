import 'package:flutter/material.dart';

import '../core/aegis_store.dart';
import '../core/herald_pipe.dart';
import '../core/net_sensor.dart';
import '../env/app_facade.dart';
import 'portal_stage.dart';

/// Push-permission promo screen — shown once, before the WebView
/// portal, unless the user has already granted or the OS has
/// permanently denied.
///
/// Buttons: Accept / Skip.  The Accept button routes into the
/// system dialog via `HeraldPipe.askPermission`; Skip snoozes
/// the promo for `AppFacade.promoCooldownSeconds` (3 days).
class PromoStage extends StatefulWidget {
  final AegisStore store;
  final HeraldPipe herald;
  final NetSensor sensor;
  final String portalUrl;

  const PromoStage({
    super.key,
    required this.store,
    required this.herald,
    required this.sensor,
    required this.portalUrl,
  });

  @override
  State<PromoStage> createState() => _PromoStageState();
}

class _PromoStageState extends State<PromoStage> {
  Future<void> _onAccept() async {
    final granted = await widget.herald.askPermission();
    if (!mounted) return;
    if (!granted) {
      final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          AppFacade.promoCooldownSeconds;
      await widget.store.writePromoSnooze(until);
    }
    _openPortal();
  }

  Future<void> _onSkip() async {
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        AppFacade.promoCooldownSeconds;
    await widget.store.writePromoSnooze(until);
    if (!mounted) return;
    _openPortal();
  }

  void _openPortal() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PortalStage(
          url: widget.portalUrl,
          store: widget.store,
          herald: widget.herald,
          sensor: widget.sensor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final landscape = size.width > size.height;
    final bg = landscape
        ? 'assets/Notifications/notif_hor.webp'
        : 'assets/Notifications/notif_vert.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF0B1A3A),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              bg,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF0B1A3A)),
            ),
            if (!landscape)
              Positioned(
                left: size.width * 0.10,
                right: size.width * 0.10,
                bottom: size.height * 0.08,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AcceptChip(onTap: _onAccept),
                    const SizedBox(height: 14),
                    _SkipChip(onTap: _onSkip),
                  ],
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: size.height * 0.06,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: size.width * 0.34,
                      child: _AcceptChip(onTap: _onAccept, tight: true),
                    ),
                    const SizedBox(height: 8),
                    _SkipChip(onTap: _onSkip, tight: true),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Custom button chips — different look than the reference
// template's gold-gradient pills.  Uses a lapis-outlined amber
// disc for Accept, and a subtle underlined text for Skip.
// ─────────────────────────────────────────────────────────────

class _AcceptChip extends StatefulWidget {
  final VoidCallback onTap;
  final bool tight;
  const _AcceptChip({required this.onTap, this.tight = false});

  @override
  State<_AcceptChip> createState() => _AcceptChipState();
}

class _AcceptChipState extends State<_AcceptChip>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _shine;

  @override
  void initState() {
    super.initState();
    _shine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shine,
      builder: (_, __) {
        return GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            padding: EdgeInsets.symmetric(
              vertical: widget.tight ? 12 : 18,
              horizontal: 24,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _pressed
                    ? const [Color(0xFFCCA23A), Color(0xFF8D5D0F)]
                    : const [Color(0xFFF4D06F), Color(0xFFB4791C)],
              ),
              border: Border.all(
                color: const Color(0xFF1E3A5F),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF4D06F).withValues(
                    alpha: _pressed ? 0.15 : 0.35 + 0.35 * _shine.value,
                  ),
                  blurRadius: _pressed ? 4 : 16 + 10 * _shine.value,
                  spreadRadius: _pressed ? 0 : 1.5 * _shine.value,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                'Accept',
                style: TextStyle(
                  color: const Color(0xFF1A0A00),
                  fontSize: widget.tight ? 16 : 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkipChip extends StatefulWidget {
  final VoidCallback onTap;
  final bool tight;
  const _SkipChip({required this.onTap, this.tight = false});

  @override
  State<_SkipChip> createState() => _SkipChipState();
}

class _SkipChipState extends State<_SkipChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.45 : 0.9,
        duration: const Duration(milliseconds: 90),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.tight ? 4 : 8),
          child: Text(
            'Skip',
            style: TextStyle(
              color: const Color(0xFFEED27B),
              fontSize: widget.tight ? 15 : 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              decoration: TextDecoration.underline,
              decorationThickness: 1.4,
              decorationColor: const Color(0xFFEED27B),
              shadows: const [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

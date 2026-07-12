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
                left: size.width * 0.14,
                right: size.width * 0.14,
                bottom: size.height * 0.09,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GoldChip(
                      label: 'Accept',
                      onTap: _onAccept,
                      pulse: true,
                    ),
                    const SizedBox(height: 12),
                    _GoldChip(
                      label: 'Skip',
                      onTap: _onSkip,
                    ),
                  ],
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: size.height * 0.07,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: size.width * 0.28,
                      child: _GoldChip(
                        label: 'Accept',
                        onTap: _onAccept,
                        pulse: true,
                        tight: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: size.width * 0.28,
                      child: _GoldChip(
                        label: 'Skip',
                        onTap: _onSkip,
                        tight: true,
                      ),
                    ),
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
// Both Accept and Skip share the same amber-gold gradient chip;
// the Accept variant pulses a subtle glow to draw the eye, the
// Skip variant sits statically for a secondary read.  Slimmer
// padding than the initial revision to keep both buttons out of
// the way of the artwork behind them.
// ─────────────────────────────────────────────────────────────

class _GoldChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool pulse;
  final bool tight;

  const _GoldChip({
    required this.label,
    required this.onTap,
    this.pulse = false,
    this.tight = false,
  });

  @override
  State<_GoldChip> createState() => _GoldChipState();
}

class _GoldChipState extends State<_GoldChip>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  AnimationController? _shine;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _shine = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
        lowerBound: 0.0,
        upperBound: 1.0,
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _shine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _shine ?? const AlwaysStoppedAnimation<double>(0.0);
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final glow = widget.pulse ? controller.value : 0.0;
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
              vertical: widget.tight ? 9 : 12,
              horizontal: 22,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _pressed
                    ? const [Color(0xFFCCA23A), Color(0xFF8D5D0F)]
                    : const [Color(0xFFF4D06F), Color(0xFFB4791C)],
              ),
              border: Border.all(
                color: const Color(0xFF1E3A5F),
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF4D06F).withValues(
                    alpha: _pressed ? 0.12 : 0.30 + 0.30 * glow,
                  ),
                  blurRadius: _pressed ? 4 : 12 + 8 * glow,
                  spreadRadius: _pressed ? 0 : 1.2 * glow,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: const Color(0xFF1A0A00),
                  fontSize: widget.tight ? 14 : 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

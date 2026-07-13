import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// No-Wi-Fi screen (the "tempest").  Uses the Egyptian sand-storm
/// artwork already shipped in `assets/nowifi/` and floats a
/// Retry button over it.  The screen unlocks device rotation so
/// the horizontal `nowifi_hor.webp` is used when the user turns
/// the device sideways; whichever screen pushes this stage next
/// re-applies its own orientation preference.
class TempestStage extends StatefulWidget {
  final WidgetBuilder retryBuilder;

  const TempestStage({super.key, required this.retryBuilder});

  @override
  State<TempestStage> createState() => _TempestStageState();
}

class _TempestStageState extends State<TempestStage>
    with SingleTickerProviderStateMixin {
  bool _reconnecting = false;
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    // Unlock rotation for the offline screen — the artwork ships
    // with a dedicated landscape variant and we want the user to
    // be able to hold the phone whichever way they prefer while
    // troubleshooting connectivity.  We apply the preference
    // twice on purpose:
    //   (1) synchronously here, and
    //   (2) again in a post-frame callback so the outgoing
    //       route's dispose() cannot silently re-lock us to
    //       portrait (Navigator.pushReplacement runs the OLD
    //       screen's dispose AFTER the new screen's initState).
    _unlockRotation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlockRotation());

    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
    _pressScale = _pressCtrl;
  }

  void _unlockRotation() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRetry() async {
    if (_reconnecting) return;
    _pressCtrl.value = 0.94;
    await Future<void>.delayed(const Duration(milliseconds: 90));
    _pressCtrl.value = 1.0;
    setState(() => _reconnecting = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.retryBuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final landscape = size.width > size.height;
    final bg = landscape
        ? 'assets/nowifi/nowifi_hor.webp'
        : 'assets/nowifi/nowifi_vert.webp';

    // Landscape gets a noticeably slimmer button (both narrower
    // and shorter) — the horizontal artwork already fills more
    // of the frame, so a large gold pill fought the composition.
    // Second iteration: tightened the margins another notch so
    // the button sits inside the plate painted into nowifi_hor.
    final horizontalMargin =
        landscape ? size.width * 0.38 : size.width * 0.10;
    final buttonHeight = landscape ? 40.0 : 60.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1A3A),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              bg,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(color: const Color(0xFF0B1A3A)),
            ),
            Positioned(
              left: horizontalMargin,
              right: horizontalMargin,
              bottom: landscape ? size.height * 0.09 : size.height * 0.09,
              child: ScaleTransition(
                scale: _pressScale,
                child: _RetryPlate(
                  reconnecting: _reconnecting,
                  onTap: _onRetry,
                  height: buttonHeight,
                  compact: landscape,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryPlate extends StatelessWidget {
  final bool reconnecting;
  final VoidCallback onTap;
  final double height;
  final bool compact;

  const _RetryPlate({
    required this.reconnecting,
    required this.onTap,
    required this.height,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
        onTap: reconnecting ? null : onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            gradient: reconnecting
                ? null
                : const LinearGradient(
                    colors: [Color(0xFFF4D06F), Color(0xFFB88418)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: reconnecting
                ? Colors.black.withValues(alpha: 0.55)
                : null,
            border: Border.all(
              color: const Color(0xFFEED27B),
              width: compact ? 1.3 : 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: compact ? 8 : 12,
                offset: Offset(0, compact ? 4 : 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: reconnecting
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: compact ? 14 : 20,
                      height: compact ? 14 : 20,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFF4D06F)),
                      ),
                    ),
                    SizedBox(width: compact ? 7 : 12),
                    Text(
                      'Reconnecting…',
                      style: TextStyle(
                        color: const Color(0xFFF4D06F),
                        fontSize: compact ? 13 : 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                )
              : Text(
                  'Try again',
                  style: TextStyle(
                    color: const Color(0xFF1A0A00),
                    fontSize: compact ? 13 : 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
        ),
      ),
    );
  }
}

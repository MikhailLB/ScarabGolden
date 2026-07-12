import 'package:flutter/material.dart';

/// No-Wi-Fi screen (the "tempest").  Uses the Egyptian sand-storm
/// artwork already shipped in `assets/nowifi/` and floats a
/// Retry button over it.
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
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
    _pressScale = _pressCtrl;
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
            Positioned(
              left: landscape ? size.width * 0.25 : size.width * 0.10,
              right: landscape ? size.width * 0.25 : size.width * 0.10,
              bottom: landscape ? size.height * 0.08 : size.height * 0.09,
              child: ScaleTransition(
                scale: _pressScale,
                child: _RetryPlate(
                  reconnecting: _reconnecting,
                  onTap: _onRetry,
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

  const _RetryPlate({required this.reconnecting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: reconnecting ? null : onTap,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
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
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: reconnecting
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFF4D06F)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Reconnecting…',
                      style: TextStyle(
                        color: Color(0xFFF4D06F),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                )
              : const Text(
                  'Try again',
                  style: TextStyle(
                    color: Color(0xFF1A0A00),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
        ),
      ),
    );
  }
}

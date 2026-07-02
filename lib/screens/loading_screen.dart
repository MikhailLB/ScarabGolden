import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  int _dots = 0;
  Timer? _tickTimer;
  Timer? _dotsTimer;
  bool _navigated = false;

  static const _totalMs = 3200;

  @override
  void initState() {
    super.initState();
    // During loading, let the user hold the phone in any orientation.
    // The background asset swaps automatically (vert vs. horizontal).
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _dotsTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted) return;
      setState(() => _dots = (_dots + 1) % 4);
    });

    // Simulate loading in small increments so bar goes 0 -> ~0.9 during
    // "loading" then jumps to 1.0 right before navigating to the menu.
    const stepMs = 60;
    final steps = _totalMs ~/ stepMs;
    int i = 0;
    _tickTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) {
      if (!mounted) return;
      i++;
      final ratio = i / steps;
      // Ease so bar slows a bit near the end, then completes.
      setState(() {
        _progress = (ratio * 0.9).clamp(0.0, 0.9);
      });
      if (i >= steps) {
        t.cancel();
        _finishAndNavigate();
      }
    });
  }

  Future<void> _finishAndNavigate() async {
    if (_navigated) return;
    _navigated = true;
    // Fill the bar completely just before launching the menu.
    setState(() => _progress = 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    // Lock back to portrait only for the actual game.
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const MenuScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _dotsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Choose vertical vs horizontal asset based on screen orientation.
    final isPortrait = size.height >= size.width;
    final bg = isPortrait
        ? 'assets/vertloading.png'
        : 'assets/loadin_hor.webp';

    return Scaffold(
      backgroundColor: AppColors.darkNavy,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              bg,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: AppColors.darkNavy),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
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
                  child: _ProgressBar(progress: _progress),
                ),
                const SizedBox(height: 18),
                Text(
                  'Loading${'.' * _dots}',
                  style: AppTextStyles.loading,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress; // 0..1
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFFD979),
                    Color(0xFFE9BE55),
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

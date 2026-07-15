import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../bridge/insight.dart';
import '../models/puzzle_level.dart';
import '../models/puzzle_state.dart';
import '../services/progress_service.dart';
import '../theme.dart';
import '../widgets/puzzle_tile.dart';

class GameScreen extends StatefulWidget {
  final PuzzleLevel level;

  const GameScreen({super.key, required this.level});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late PuzzleState _state;
  final _progress = ProgressService();

  Timer? _clockTimer;
  int _seconds = 0;
  bool _completed = false;
  bool _previewOpen = false;

  @override
  void initState() {
    super.initState();
    Insight.screen('game');
    Insight.tag('level', '${widget.level.index}');
    _startNewGame();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _startNewGame() {
    _clockTimer?.cancel();
    _state = PuzzleState.shuffled(
      widget.level.gridSize,
      seed: DateTime.now().millisecondsSinceEpoch,
    );
    _seconds = 0;
    _completed = false;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _completed) return;
      setState(() => _seconds++);
    });
    setState(() {});
  }

  void _onTapTile(int row, int col) {
    if (_completed) return;
    final moved = _state.slide(row, col);
    if (!moved) return;
    setState(() {});
    if (_state.isSolved) {
      _completed = true;
      _clockTimer?.cancel();
      _handleWin();
    }
  }

  Future<void> _handleWin() async {
    await _progress.recordCompletion(
      level: widget.level.index,
      moves: _state.moves,
      seconds: _seconds,
    );
    if (!mounted) return;
    // Small delay so the player sees the completed image before the dialog.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WinDialog(
        level: widget.level,
        moves: _state.moves,
        seconds: _seconds,
        onReplay: () {
          Navigator.of(ctx).pop();
          _startNewGame();
        },
        onNext: () {
          Navigator.of(ctx).pop();
          _goNext();
        },
        onMenu: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _goNext() {
    final all = PuzzleLevels.all;
    if (widget.level.index < all.length) {
      final next = all[widget.level.index]; // level.index is 1-based
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(level: next)),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkNavy,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/menubg.webp',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: AppColors.darkNavy),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
          SafeArea(
            child: Column(
              children: [
                _Header(
                  level: widget.level,
                  onBack: () => Navigator.of(context).pop(),
                  onReset: _startNewGame,
                ),
                const SizedBox(height: 4),
                _Stats(
                  moves: _state.moves,
                  time: _formatTime(_seconds),
                  onTogglePreview: () =>
                      setState(() => _previewOpen = !_previewOpen),
                  previewOpen: _previewOpen,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, constraints) => _Board(
                      state: _state,
                      level: widget.level,
                      constraints: constraints,
                      onTapTile: _onTapTile,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
          if (_previewOpen)
            _PreviewOverlay(
              imagePath: widget.level.imagePath,
              name: widget.level.name,
              onClose: () => setState(() => _previewOpen = false),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PuzzleLevel level;
  final VoidCallback onBack;
  final VoidCallback onReset;

  const _Header({
    required this.level,
    required this.onBack,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.goldLight),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'LEVEL ${level.index}',
                  style: AppTextStyles.title.copyWith(fontSize: 22),
                ),
                Text(
                  '${level.name} · ${level.gridSize}×${level.gridSize}',
                  style: const TextStyle(
                    color: AppColors.parchment,
                    fontSize: 13,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.goldLight, size: 28),
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  final int moves;
  final String time;
  final VoidCallback onTogglePreview;
  final bool previewOpen;

  const _Stats({
    required this.moves,
    required this.time,
    required this.onTogglePreview,
    required this.previewOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Chip(icon: Icons.swap_horiz_rounded, label: 'Moves', value: '$moves'),
          _Chip(icon: Icons.timer_outlined, label: 'Time', value: time),
          _PreviewButton(active: previewOpen, onTap: onTogglePreview),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Chip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.goldLight),
          const SizedBox(width: 6),
          Text('$label ',
              style: const TextStyle(
                color: AppColors.parchment,
                fontSize: 12,
              )),
          Text(value,
              style: const TextStyle(
                color: AppColors.goldLight,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              )),
        ],
      ),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _PreviewButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.gold : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.gold, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18,
              color: active ? AppColors.darkNavy : AppColors.goldLight,
            ),
            const SizedBox(width: 6),
            Text(
              active ? 'Hide' : 'Goal',
              style: TextStyle(
                color: active ? AppColors.darkNavy : AppColors.goldLight,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  final PuzzleState state;
  final PuzzleLevel level;
  final BoxConstraints constraints;
  final void Function(int row, int col) onTapTile;

  const _Board({
    required this.state,
    required this.level,
    required this.constraints,
    required this.onTapTile,
  });

  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    final n = state.n;
    final maxSide = min(constraints.maxWidth - 24, constraints.maxHeight - 24);
    final boardSide = maxSide.floorToDouble();
    // Reserve gap*(n+1) for spacing.
    final tileSize = ((boardSide - _gap * (n + 1)) / n).floorToDouble();
    final actualSide = tileSize * n + _gap * (n + 1);

    // For animation between positions, we place tiles by tile id in a Stack
    // and drive their Positioned offsets from the current tile positions.
    final positions = state.currentIndices();

    return Center(
      child: Container(
        width: actualSide,
        height: actualSide,
        padding: const EdgeInsets.all(_gap),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF13285C), Color(0xFF071233)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.gold, width: 2.4),
          boxShadow: const [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          width: actualSide - _gap * 2,
          height: actualSide - _gap * 2,
          child: Stack(
            children: [
              for (int tileId = 0; tileId < n * n; tileId++)
                AnimatedPositioned(
                  key: ValueKey('tile_$tileId'),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  left: (positions[tileId] % n) * (tileSize + _gap),
                  top: (positions[tileId] ~/ n) * (tileSize + _gap),
                  width: tileSize,
                  height: tileSize,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final idx = positions[tileId];
                      onTapTile(idx ~/ n, idx % n);
                    },
                    child: PuzzleTile(
                      tileId: tileId,
                      gridSize: n,
                      size: tileSize,
                      imagePath: level.imagePath,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewOverlay extends StatelessWidget {
  final String imagePath;
  final String name;
  final VoidCallback onClose;

  const _PreviewOverlay({
    required this.imagePath,
    required this.name,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.82),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: AppTextStyles.title.copyWith(fontSize: 22)),
                  const SizedBox(height: 14),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 30),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.gold, width: 2.5),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black87,
                          blurRadius: 20,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image.asset(imagePath, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Tap anywhere to close',
                    style: TextStyle(color: AppColors.parchment, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WinDialog extends StatelessWidget {
  final PuzzleLevel level;
  final int moves;
  final int seconds;
  final VoidCallback onReplay;
  final VoidCallback onNext;
  final VoidCallback onMenu;

  const _WinDialog({
    required this.level,
    required this.moves,
    required this.seconds,
    required this.onReplay,
    required this.onNext,
    required this.onMenu,
  });

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isLast = level.index >= PuzzleLevels.all.length;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 30),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF13285C), Color(0xFF071233)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gold, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded,
                color: AppColors.goldLight, size: 68),
            const SizedBox(height: 6),
            Text(
              isLast ? 'ALL LEVELS DONE!' : 'PUZZLE SOLVED',
              style: AppTextStyles.title.copyWith(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(level.name,
                style: const TextStyle(
                  color: AppColors.parchment,
                  fontSize: 14,
                )),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _WinStat(label: 'MOVES', value: '$moves'),
                _WinStat(label: 'TIME', value: _fmt(seconds)),
              ],
            ),
            const SizedBox(height: 22),
            if (!isLast)
              _DialogButton(
                label: 'NEXT LEVEL',
                icon: Icons.play_arrow_rounded,
                onTap: onNext,
              ),
            if (!isLast) const SizedBox(height: 10),
            _DialogButton(
              label: 'PLAY AGAIN',
              icon: Icons.refresh_rounded,
              onTap: onReplay,
              outline: true,
            ),
            const SizedBox(height: 10),
            _DialogButton(
              label: 'MAIN MENU',
              icon: Icons.home_rounded,
              onTap: onMenu,
              outline: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _WinStat extends StatelessWidget {
  final String label;
  final String value;
  const _WinStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
              color: AppColors.parchment,
              fontSize: 12,
              letterSpacing: 1.2,
            )),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
              color: AppColors.goldLight,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            )),
      ],
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool outline;
  const _DialogButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.outline = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        height: 50,
        decoration: BoxDecoration(
          color: outline ? Colors.transparent : AppColors.gold,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold, width: 2),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: outline ? AppColors.goldLight : AppColors.darkNavy),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: outline ? AppColors.goldLight : AppColors.darkNavy,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

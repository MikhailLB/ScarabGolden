import 'package:flutter/material.dart';

import '../models/puzzle_level.dart';
import '../services/progress_service.dart';
import '../theme.dart';
import 'game_screen.dart';

class LevelsScreen extends StatefulWidget {
  const LevelsScreen({super.key});

  @override
  State<LevelsScreen> createState() => _LevelsScreenState();
}

class _LevelsScreenState extends State<LevelsScreen> {
  final _progress = ProgressService();
  Set<int> _completed = {};
  final Map<int, int?> _bestMoves = {};
  final Map<int, int?> _bestTime = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _progress.getCompleted();
    for (final l in PuzzleLevels.all) {
      _bestMoves[l.index] = await _progress.getBestMoves(l.index);
      _bestTime[l.index] = await _progress.getBestTimeSeconds(l.index);
    }
    if (!mounted) return;
    setState(() {
      _completed = c;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: AppColors.goldLight),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text('SELECT LEVEL',
                              style: AppTextStyles.title),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    itemCount: PuzzleLevels.all.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (ctx, i) {
                      final level = PuzzleLevels.all[i];
                      return _LevelCard(
                        level: level,
                        completed: _completed.contains(level.index),
                        bestMoves: _bestMoves[level.index],
                        bestTime: _bestTime[level.index],
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => GameScreen(level: level),
                            ),
                          );
                          _load();
                        },
                      );
                    },
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

class _LevelCard extends StatelessWidget {
  final PuzzleLevel level;
  final bool completed;
  final int? bestMoves;
  final int? bestTime;
  final VoidCallback onTap;

  const _LevelCard({
    required this.level,
    required this.completed,
    required this.bestMoves,
    required this.bestTime,
    required this.onTap,
  });

  String _fmtTime(int? s) {
    if (s == null) return '—';
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF13285C), Color(0xFF0A173E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold, width: 2.2),
          boxShadow: const [
            BoxShadow(
                color: Colors.black45,
                blurRadius: 10,
                offset: Offset(0, 4)),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: Image.asset(
                      level.imagePath,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'LEVEL ${level.index}',
                        style: const TextStyle(
                          color: AppColors.goldLight,
                          fontSize: 13,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        level.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.goldLight,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.grid_view_rounded,
                              size: 14, color: AppColors.parchment),
                          const SizedBox(width: 4),
                          Text(
                            '${level.gridSize}×${level.gridSize}',
                            style: const TextStyle(
                                color: AppColors.parchment, fontSize: 12),
                          ),
                          const SizedBox(width: 14),
                          const Icon(Icons.swap_horiz_rounded,
                              size: 14, color: AppColors.parchment),
                          const SizedBox(width: 4),
                          Text(
                            bestMoves == null ? '—' : '$bestMoves',
                            style: const TextStyle(
                                color: AppColors.parchment, fontSize: 12),
                          ),
                          const SizedBox(width: 14),
                          const Icon(Icons.timer_outlined,
                              size: 14, color: AppColors.parchment),
                          const SizedBox(width: 4),
                          Text(
                            _fmtTime(bestTime),
                            style: const TextStyle(
                                color: AppColors.parchment, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (completed)
                      const Icon(Icons.star_rounded,
                          color: AppColors.goldLight, size: 28),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.goldLight, size: 34),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

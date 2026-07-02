import 'package:shared_preferences/shared_preferences.dart';

/// Persists which levels have been completed and the best (lowest) move
/// count per level.
class ProgressService {
  static const _kCompletedKey = 'completed_levels';
  static const _kBestMovesPrefix = 'best_moves_';
  static const _kBestTimePrefix = 'best_time_';

  Future<Set<int>> getCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kCompletedKey) ?? [];
    return list.map(int.parse).toSet();
  }

  Future<int?> getBestMoves(int level) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('$_kBestMovesPrefix$level');
    return v == 0 ? null : v;
  }

  Future<int?> getBestTimeSeconds(int level) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('$_kBestTimePrefix$level');
    return v == 0 ? null : v;
  }

  /// Marks a level complete and updates the best moves / time if better.
  Future<void> recordCompletion({
    required int level,
    required int moves,
    required int seconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final completed = (prefs.getStringList(_kCompletedKey) ?? [])
        .map(int.parse)
        .toSet();
    completed.add(level);
    await prefs.setStringList(
      _kCompletedKey,
      completed.map((e) => e.toString()).toList(),
    );

    final movesKey = '$_kBestMovesPrefix$level';
    final prevMoves = prefs.getInt(movesKey);
    if (prevMoves == null || prevMoves == 0 || moves < prevMoves) {
      await prefs.setInt(movesKey, moves);
    }

    final timeKey = '$_kBestTimePrefix$level';
    final prevTime = prefs.getInt(timeKey);
    if (prevTime == null || prevTime == 0 || seconds < prevTime) {
      await prefs.setInt(timeKey, seconds);
    }
  }
}

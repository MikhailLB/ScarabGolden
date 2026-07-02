import 'dart:math';

/// State of a sliding puzzle. The board is a flat list of length `n * n`
/// where each entry is a tile id in `[0, n*n - 1]`. Tile id `0` represents
/// the empty slot.
///
/// A tile with id `k` (k > 0) belongs at position `k - 1` in the solved
/// board. The empty tile (id 0) belongs at the last position `n * n - 1`.
class PuzzleState {
  final int n;
  final List<int> tiles;
  int moves;

  PuzzleState._(this.n, this.tiles, this.moves);

  factory PuzzleState.solved(int n) {
    final total = n * n;
    final tiles = List<int>.generate(total, (i) => (i + 1) % total);
    return PuzzleState._(n, tiles, 0);
  }

  /// Creates a shuffled but solvable puzzle by performing many random valid
  /// moves from the solved state.
  factory PuzzleState.shuffled(int n, {int? seed}) {
    final rng = Random(seed);
    final state = PuzzleState.solved(n);
    // More moves for bigger boards so the shuffle is genuinely hard.
    final steps = 60 * n * n;
    int lastDir = -1;
    for (int i = 0; i < steps; i++) {
      final emptyIdx = state.tiles.indexOf(0);
      final neighbours = state._neighbourIndices(emptyIdx);
      // Avoid immediately undoing the previous move.
      final options = neighbours.where((entry) {
        final dir = entry.$2;
        return dir != _oppositeDir(lastDir);
      }).toList();
      final pool = options.isEmpty ? neighbours : options;
      final pick = pool[rng.nextInt(pool.length)];
      state._swap(emptyIdx, pick.$1);
      lastDir = pick.$2;
    }
    state.moves = 0;
    // Extremely rare: if we shuffled back into the solved state, do one more
    // guaranteed move to break it.
    if (state.isSolved) {
      final emptyIdx = state.tiles.indexOf(0);
      final n2 = state._neighbourIndices(emptyIdx);
      state._swap(emptyIdx, n2.first.$1);
      state.moves = 0;
    }
    return state;
  }

  bool get isSolved {
    for (int i = 0; i < tiles.length; i++) {
      if (tiles[i] != (i + 1) % tiles.length) return false;
    }
    return true;
  }

  int indexOfTile(int tileId) => tiles.indexOf(tileId);

  int rowOf(int index) => index ~/ n;
  int colOf(int index) => index % n;

  /// Attempts to slide the tile at (row, col). Returns true if a move happened.
  bool slide(int row, int col) {
    final idx = row * n + col;
    if (tiles[idx] == 0) return false;
    final emptyIdx = tiles.indexOf(0);
    final er = emptyIdx ~/ n;
    final ec = emptyIdx % n;
    final dr = (er - row).abs();
    final dc = (ec - col).abs();
    if (dr + dc != 1) return false;
    _swap(idx, emptyIdx);
    moves++;
    return true;
  }

  /// Returns positions currently occupied by each tile id (in solved order).
  List<int> currentIndices() {
    final positions = List<int>.filled(tiles.length, 0);
    for (int i = 0; i < tiles.length; i++) {
      positions[tiles[i]] = i;
    }
    return positions;
  }

  void _swap(int a, int b) {
    final tmp = tiles[a];
    tiles[a] = tiles[b];
    tiles[b] = tmp;
  }

  /// Returns `[(neighbourIndex, direction), ...]` for the given cell.
  /// Direction codes: 0 = up, 1 = right, 2 = down, 3 = left.
  List<(int, int)> _neighbourIndices(int idx) {
    final r = idx ~/ n;
    final c = idx % n;
    final result = <(int, int)>[];
    if (r > 0) result.add((idx - n, 0));
    if (c < n - 1) result.add((idx + 1, 1));
    if (r < n - 1) result.add((idx + n, 2));
    if (c > 0) result.add((idx - 1, 3));
    return result;
  }

  static int _oppositeDir(int d) => d < 0 ? -1 : (d + 2) % 4;
}

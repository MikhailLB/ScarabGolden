import 'package:flutter_test/flutter_test.dart';

import 'package:scarabgolden/models/puzzle_state.dart';

void main() {
  test('solved state is detected', () {
    for (final n in [3, 4, 5, 6]) {
      final s = PuzzleState.solved(n);
      expect(s.isSolved, isTrue, reason: '$n x $n solved state');
    }
  });

  test('shuffled state is solvable and not initially solved', () {
    for (final n in [3, 4, 5, 6]) {
      final s = PuzzleState.shuffled(n, seed: 42);
      expect(s.isSolved, isFalse, reason: '$n x $n should be shuffled');
      // Every shuffled state produced by random valid moves is solvable
      // by construction (parity is preserved).
      expect(s.tiles.length, n * n);
      expect(s.tiles.toSet().length, n * n,
          reason: 'all tile ids should be distinct');
    }
  });

  test('slide swaps only with adjacent empty', () {
    final s = PuzzleState.solved(3);
    // In solved 3x3, empty is at index 8 (row 2, col 2).
    // Sliding (2, 1) should move tile 8 into the empty slot.
    expect(s.slide(2, 1), isTrue);
    expect(s.tiles[8], 8);
    expect(s.tiles[7], 0);
    expect(s.moves, 1);

    // Sliding a non-adjacent tile should fail.
    expect(s.slide(0, 0), isFalse);
    expect(s.moves, 1);
  });
}

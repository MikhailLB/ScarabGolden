class PuzzleLevel {
  final int index; // 1-based
  final String name;
  final int gridSize; // NxN
  final String imagePath;

  const PuzzleLevel({
    required this.index,
    required this.name,
    required this.gridSize,
    required this.imagePath,
  });

  int get tileCount => gridSize * gridSize;
}

class PuzzleLevels {
  static const List<PuzzleLevel> all = [
    PuzzleLevel(
      index: 1,
      name: 'Sacred Scarab',
      gridSize: 3,
      imagePath: 'assets/scarab.jpg',
    ),
    PuzzleLevel(
      index: 2,
      name: 'Golden Pharaoh',
      gridSize: 4,
      imagePath: 'assets/pharaoh.jpg',
    ),
    PuzzleLevel(
      index: 3,
      name: 'Anubis Guardian',
      gridSize: 5,
      imagePath: 'assets/anubis.jpg',
    ),
    PuzzleLevel(
      index: 4,
      name: 'Ancient Nile',
      gridSize: 6,
      imagePath: 'assets/anciant.jpg',
    ),
  ];
}

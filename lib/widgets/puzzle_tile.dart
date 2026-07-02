import 'package:flutter/material.dart';

import '../theme.dart';

/// A single sliding-puzzle tile. Renders a specific rectangular portion of
/// the source image (defined by the tile's ORIGINAL solved position) at the
/// given [size]. The empty tile is rendered as a subtle dark socket.
class PuzzleTile extends StatelessWidget {
  final int tileId; // 0 = empty
  final int gridSize;
  final double size;
  final String imagePath;

  const PuzzleTile({
    super.key,
    required this.tileId,
    required this.gridSize,
    required this.size,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    if (tileId == 0) {
      return _EmptySlot(size: size);
    }

    // Tile with id k belongs at solved position k - 1. Split the source
    // image into a gridSize x gridSize grid and show the portion at
    // (solvedRow, solvedCol).
    final solvedIdx = tileId - 1;
    final solvedRow = solvedIdx ~/ gridSize;
    final solvedCol = solvedIdx % gridSize;

    final imgSide = size * gridSize;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.55), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 4,
            offset: Offset(1, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -solvedCol * size,
              top: -solvedRow * size,
              width: imgSide,
              height: imgSide,
              child: Image.asset(
                imagePath,
                width: imgSide,
                height: imgSide,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final double size;
  const _EmptySlot({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black45, width: 1),
      ),
    );
  }
}

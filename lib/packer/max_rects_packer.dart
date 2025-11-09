import 'dart:math' as math;

import 'rect.dart';

enum MaxRectsHeuristic { bestShortSide, bestArea }

class MaxRectsBin {
  MaxRectsBin({
    required this.width,
    required this.height,
    this.allowRotations = true,
    this.heuristic = MaxRectsHeuristic.bestShortSide,
  }) {
    reset();
  }

  final int width;
  final int height;
  final bool allowRotations;
  final MaxRectsHeuristic heuristic;

  final List<RectInt> freeRectangles = [];
  final List<RectInt> usedRectangles = [];

  void reset() {
    freeRectangles
      ..clear()
      ..add(RectInt(x: 0, y: 0, width: width, height: height));
    usedRectangles.clear();
  }

  RectInt? insert(int rectWidth, int rectHeight) {
    final RectInt? newNode = switch (heuristic) {
      MaxRectsHeuristic.bestShortSide => _findPositionBestShortSide(
        rectWidth,
        rectHeight,
      ),
      MaxRectsHeuristic.bestArea => _findPositionBestArea(
        rectWidth,
        rectHeight,
      ),
    };

    if (newNode == null || newNode.height == 0) {
      return null;
    }

    _placeRect(newNode);
    return newNode;
  }

  RectInt? _findPositionBestShortSide(int rectWidth, int rectHeight) {
    RectInt? bestNode;
    var bestShortSide = math.max(width, height);
    var bestLongSide = math.max(width, height);

    for (final freeRect in freeRectangles) {
      if (freeRect.width >= rectWidth && freeRect.height >= rectHeight) {
        final leftoverHoriz = (freeRect.width - rectWidth).abs();
        final leftoverVert = (freeRect.height - rectHeight).abs();
        final shortSide = math.min(leftoverHoriz, leftoverVert);
        final longSide = math.max(leftoverHoriz, leftoverVert);

        if (shortSide < bestShortSide ||
            (shortSide == bestShortSide && longSide < bestLongSide)) {
          bestNode = RectInt(
            x: freeRect.x,
            y: freeRect.y,
            width: rectWidth,
            height: rectHeight,
          );
          bestShortSide = shortSide;
          bestLongSide = longSide;
        }
      }

      if (allowRotations &&
          freeRect.width >= rectHeight &&
          freeRect.height >= rectWidth) {
        final leftoverHoriz = (freeRect.width - rectHeight).abs();
        final leftoverVert = (freeRect.height - rectWidth).abs();
        final shortSide = math.min(leftoverHoriz, leftoverVert);
        final longSide = math.max(leftoverHoriz, leftoverVert);

        if (shortSide < bestShortSide ||
            (shortSide == bestShortSide && longSide < bestLongSide)) {
          bestNode = RectInt(
            x: freeRect.x,
            y: freeRect.y,
            width: rectHeight,
            height: rectWidth,
          );
          bestShortSide = shortSide;
          bestLongSide = longSide;
        }
      }
    }

    return bestNode;
  }

  RectInt? _findPositionBestArea(int rectWidth, int rectHeight) {
    RectInt? bestNode;
    var bestAreaFit = width * height;
    var bestShortSide = width * height;

    for (final freeRect in freeRectangles) {
      final areaFit = freeRect.width * freeRect.height - rectWidth * rectHeight;

      if (freeRect.width >= rectWidth && freeRect.height >= rectHeight) {
        final leftoverHoriz = (freeRect.width - rectWidth).abs();
        final leftoverVert = (freeRect.height - rectHeight).abs();
        final shortSide = math.min(leftoverHoriz, leftoverVert);

        if (areaFit < bestAreaFit ||
            (areaFit == bestAreaFit && shortSide < bestShortSide)) {
          bestNode = RectInt(
            x: freeRect.x,
            y: freeRect.y,
            width: rectWidth,
            height: rectHeight,
          );
          bestAreaFit = areaFit;
          bestShortSide = shortSide;
        }
      }

      if (allowRotations &&
          freeRect.width >= rectHeight &&
          freeRect.height >= rectWidth) {
        final leftoverHoriz = (freeRect.width - rectHeight).abs();
        final leftoverVert = (freeRect.height - rectWidth).abs();
        final shortSide = math.min(leftoverHoriz, leftoverVert);

        if (areaFit < bestAreaFit ||
            (areaFit == bestAreaFit && shortSide < bestShortSide)) {
          bestNode = RectInt(
            x: freeRect.x,
            y: freeRect.y,
            width: rectHeight,
            height: rectWidth,
          );
          bestAreaFit = areaFit;
          bestShortSide = shortSide;
        }
      }
    }

    return bestNode;
  }

  void _placeRect(RectInt node) {
    final List<RectInt> toProcess = [];
    final List<RectInt> newRects = [];
    for (final rect in freeRectangles) {
      if (_splitFreeNode(rect, node, newRects)) {
        toProcess.add(rect);
      }
    }
    freeRectangles
      ..removeWhere(toProcess.contains)
      ..addAll(newRects);
    _pruneFreeList();
    usedRectangles.add(node);
  }

  bool _splitFreeNode(
    RectInt freeRect,
    RectInt usedRect,
    List<RectInt> accumulator,
  ) {
    if (usedRect.x >= freeRect.right ||
        usedRect.right <= freeRect.x ||
        usedRect.y >= freeRect.bottom ||
        usedRect.bottom <= freeRect.y) {
      return false;
    }

    if (usedRect.x < freeRect.right && usedRect.right > freeRect.x) {
      if (usedRect.y > freeRect.y && usedRect.y < freeRect.bottom) {
        accumulator.add(
          RectInt(
            x: freeRect.x,
            y: freeRect.y,
            width: freeRect.width,
            height: usedRect.y - freeRect.y,
          ),
        );
      }

      if (usedRect.bottom < freeRect.bottom) {
        accumulator.add(
          RectInt(
            x: freeRect.x,
            y: usedRect.bottom,
            width: freeRect.width,
            height: freeRect.bottom - usedRect.bottom,
          ),
        );
      }
    }

    if (usedRect.y < freeRect.bottom && usedRect.bottom > freeRect.y) {
      if (usedRect.x > freeRect.x && usedRect.x < freeRect.right) {
        accumulator.add(
          RectInt(
            x: freeRect.x,
            y: freeRect.y,
            width: usedRect.x - freeRect.x,
            height: freeRect.height,
          ),
        );
      }

      if (usedRect.right < freeRect.right) {
        accumulator.add(
          RectInt(
            x: usedRect.right,
            y: freeRect.y,
            width: freeRect.right - usedRect.right,
            height: freeRect.height,
          ),
        );
      }
    }

    return true;
  }

  void _pruneFreeList() {
    for (var i = 0; i < freeRectangles.length; i++) {
      for (var j = i + 1; j < freeRectangles.length; j++) {
        final rect1 = freeRectangles[i];
        final rect2 = freeRectangles[j];
        if (_isContainedIn(rect1, rect2)) {
          freeRectangles.removeAt(i);
          i--;
          break;
        }
        if (_isContainedIn(rect2, rect1)) {
          freeRectangles.removeAt(j);
          j--;
        }
      }
    }
  }

  bool _isContainedIn(RectInt a, RectInt b) {
    return a.x >= b.x &&
        a.y >= b.y &&
        a.right <= b.right &&
        a.bottom <= b.bottom;
  }
}

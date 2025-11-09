class RectInt {
  const RectInt({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  int get right => x + width;
  int get bottom => y + height;

  RectInt translate(int dx, int dy) =>
      RectInt(x: x + dx, y: y + dy, width: width, height: height);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RectInt &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'RectInt(x: $x, y: $y, width: $width, height: $height)';
}

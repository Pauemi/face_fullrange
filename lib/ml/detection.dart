class Detection {
  final double score;
  final double xMin;
  final double yMin;
  final double width;
  final double height;

  Detection({
    required this.score,
    required this.xMin,
    required this.yMin,
    required this.width,
    required this.height,
  });

  double get xMax => xMin + width;
  double get yMax => yMin + height;
}

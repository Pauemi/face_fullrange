import 'dart:math' as math;

import 'detection.dart';

List<Detection> nonMaxSuppression(List<Detection> input, double iouThreshold) {
  // Filtra y ordena desc
  final detections = List<Detection>.from(input);
  detections.sort((a, b) => b.score.compareTo(a.score));

  final suppressed = List<bool>.filled(detections.length, false);
  final result = <Detection>[];

  for (int i = 0; i < detections.length; i++) {
    if (suppressed[i]) continue;
    final dA = detections[i];
    result.add(dA);

    for (int j = i + 1; j < detections.length; j++) {
      if (suppressed[j]) continue;
      final dB = detections[j];
      final iou = calculateIOU(dA, dB);
      if (iou >= iouThreshold) suppressed[j] = true;
    }
  }
  return result;
}

double calculateIOU(Detection a, Detection b) {
  final xMin = math.max(a.xMin, b.xMin);
  final yMin = math.max(a.yMin, b.yMin);
  final xMax = math.min(a.xMax, b.xMax);
  final yMax = math.min(a.yMax, b.yMax);

  if (xMax <= xMin || yMax <= yMin) return 0.0;

  final intersectArea = (xMax - xMin) * (yMax - yMin);
  final unionArea = (a.width * a.height) + (b.width * b.height) - intersectArea;
  return intersectArea / unionArea;
}

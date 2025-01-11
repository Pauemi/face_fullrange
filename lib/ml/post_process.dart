import 'dart:math' as math;

import 'anchors.dart';
import 'detection.dart';
import 'nms.dart';

/// Decodifica la salida cruda del modelo (boxes, scores) en detecciones.
List<Detection> decodeFullRange({
  required List<List<List<double>>> boxesRaw,
  required List<List<List<double>>> scoresRaw,
  required List<Anchor> anchors,
  double scoreThreshold = MIN_SCORE_THRESH,
  double iouThreshold = 0.3,
}) {
  final detections = <Detection>[];
  
  print('🔄 Iniciando decodificación de ${boxesRaw[0].length} cajas');

  for (int i = 0; i < boxesRaw[0].length; i++) {
    // Aplicar sigmoide al score
    final rawLogit = scoresRaw[0][i][0];
    final score = 1.0 / (1.0 + math.exp(-rawLogit));
    
    if (score < scoreThreshold) continue;

    // Extraer coordenadas usando las escalas correctas del modelo
    final dy = boxesRaw[0][i][0] / Y_SCALE;
    final dx = boxesRaw[0][i][1] / X_SCALE;
    final dh = boxesRaw[0][i][2] / H_SCALE;
    final dw = boxesRaw[0][i][3] / W_SCALE;
    
    final anchor = anchors[i];

    // Decodificar usando las anclas
    final yCenter = dy * anchor.h + anchor.yCenter;
    final xCenter = dx * anchor.w + anchor.xCenter;
    final h = dh * anchor.h;
    final w = dw * anchor.w;

    // Convertir a coordenadas de esquina
    final xMin = xCenter - w / 2;
    final yMin = yCenter - h / 2;

    // Validar coordenadas
    if (xMin < 0 || yMin < 0 || xMin + w > 1 || yMin + h > 1) continue;

    detections.add(Detection(
      score: score,
      xMin: xMin,
      yMin: yMin,
      width: w,
      height: h,
    ));
    
    print('📦 Detección ${detections.length}: score=$score, box=[$xMin,$yMin,$w,$h]');
  }

  // Aplicar NMS
  final finalDetections = nonMaxSuppression(detections, iouThreshold);
  print('✅ Detecciones finales después de NMS: ${finalDetections.length}');
  
  return finalDetections;
}

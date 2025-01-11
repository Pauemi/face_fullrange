import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ml/detection.dart';

class FaceDetectionPainter extends CustomPainter {
  final ui.Image image;
  final List<Detection> detections;
  final Size originalSize;

  FaceDetectionPainter({
    required this.image,
    required this.detections,
    required this.originalSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    print('🎨 Iniciando pintado de ${detections.length} detecciones');
    
    final originalWidth = originalSize.width;
    final originalHeight = originalSize.height;

    final scale = math.min(
      size.width / originalWidth,
      size.height / originalHeight
    );
    final offsetX = (size.width - originalWidth * scale) / 2;
    final offsetY = (size.height - originalHeight * scale) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red;

    for (final det in detections) {
      final rect = Rect.fromLTWH(
        det.xMin * originalWidth * scale + offsetX,
        det.yMin * originalHeight * scale + offsetY,
        det.width * originalWidth * scale,
        det.height * originalHeight * scale,
      );
      canvas.drawRect(rect, paint);
      
      // Opcional: dibujar el score
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${(det.score * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: Colors.red,
            fontSize: 16,
            backgroundColor: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      
      textPainter.paint(canvas, 
        Offset(rect.left, rect.top - 20)
      );
    }
    
    print('✅ Pintado completado');
  }

  @override
  bool shouldRepaint(covariant FaceDetectionPainter oldDelegate) {
    return oldDelegate.image != image || 
           oldDelegate.detections.length != detections.length ||
           oldDelegate.originalSize != originalSize;
  }
}

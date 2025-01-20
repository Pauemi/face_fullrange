// lib/widgets/face_detection_painter.dart

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
    // Escalar factores
    double scaleX = size.width / originalSize.width;
    double scaleY = size.height / originalSize.height;

    // Dibujar cajas de detección
    final boxPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (var detection in detections) {
      // Ajustar las coordenadas
      double left = detection.xMin * originalSize.width * scaleX;
      double top = detection.yMin * originalSize.height * scaleY;
      double width = detection.width * originalSize.width * scaleX;
      double height = detection.height * originalSize.height * scaleY;

      // Crear rectángulo de la detección
      Rect rect = Rect.fromLTWH(left, top, width, height);
      canvas.drawRect(rect, boxPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceDetectionPainter oldDelegate) {
    return image != oldDelegate.image ||
        detections != oldDelegate.detections ||
        originalSize != oldDelegate.originalSize;
  }
}

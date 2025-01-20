// lib/ml/utilities.dart
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:image/image.dart';


/// Aplica la función sigmoid a un valor dado.
double sigmoid(double x) {
  return 1 / (1 + math.exp(-x));
}

/// Clase de tupla para retornar múltiples valores
class Tuple3<T1, T2, T3> {
  final T1 item1;
  final T2 item2;
  final T3 item3;

  Tuple3(this.item1, this.item2, this.item3);
}

/// Redimensiona una imagen con letterboxing para mantener la relación de aspecto.
///
/// Retorna una tupla que contiene la imagen redimensionada y los offsets aplicados.
Tuple3<img.Image, int, int> resizeWithLetterboxing(
    img.Image image, int targetWidth, int targetHeight) {
  double originalAspect = image.width / image.height;
  double targetAspect = targetWidth / targetHeight.toDouble();

  int newWidth, newHeight;
  int padX = 0, padY = 0;

  if (originalAspect > targetAspect) {
    newWidth = targetWidth;
    newHeight = (targetWidth / originalAspect).round();
    padY = ((targetHeight - newHeight) / 2).round();
  } else {
    newHeight = targetHeight;
    newWidth = (targetHeight * originalAspect).round();
    padX = ((targetWidth - newWidth) / 2).round();
  }

  // Redimensionar la imagen original
  img.Image resized = img.copyResize(
    image,
    width: newWidth,
    height: newHeight,
    interpolation: img.Interpolation.linear,
  );

  // Crear una nueva imagen con las dimensiones objetivo y rellenarla con negro
  img.Image letterboxed = img.Image(width: targetWidth, height: targetHeight);
  img.fill(letterboxed, color: ColorFloat64.rgba(0, 0, 0, 1)  ); // Rellenar con negro opaco

  // Componer la imagen redimensionada sobre la imagen letterboxed
  img.compositeImage(
    letterboxed,
    resized,
    dstX: padX,
    dstY: padY,
    blend: img.BlendMode.alpha,
   ); // Usar BlendMode adecuado  );

  return Tuple3(letterboxed, padX, padY);
}
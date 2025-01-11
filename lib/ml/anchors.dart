

class Anchor {
  final double xCenter;
  final double yCenter;
  final double w;
  final double h;

  Anchor(this.xCenter, this.yCenter, this.w, this.h);
}

class AnchorOption {
  final int numLayers;
  final int inputSizeWidth;
  final int inputSizeHeight;
  final double anchorOffsetX;
  final double anchorOffsetY;
  final List<int> strides;
  final double interpolatedScaleAspectRatio;
  // ... más si las necesitas (minScale, maxScale, etc.)

  AnchorOption({
    required this.numLayers,
    required this.inputSizeWidth,
    required this.inputSizeHeight,
    required this.anchorOffsetX,
    required this.anchorOffsetY,
    required this.strides,
    required this.interpolatedScaleAspectRatio,
  });
}

// Constantes según el modelo
const double MODEL_INPUT_SIZE = 192.0;
const int NUM_BOXES = 2304;  // 48x48 grid
const double MIN_SCORE_THRESH = 0.6;
const double X_SCALE = 192.0;
const double Y_SCALE = 192.0;
const double H_SCALE = 192.0;
const double W_SCALE = 192.0;

List<Anchor> generateSSDAnchors(AnchorOption opts) {
  final anchors = <Anchor>[];
  print('📐 Generando anclas con stride=${opts.strides[0]}');

  // Con stride=4 en una imagen de 192x192, tenemos un grid de 48x48
  final stride = opts.strides[0];
  final gridSize = (MODEL_INPUT_SIZE / stride).floor();
  print('📏 Tamaño del grid: ${gridSize}x${gridSize}');

  // Una ancla por celda del grid
  for (int y = 0; y < gridSize; y++) {
    for (int x = 0; x < gridSize; x++) {
      final xCenter = (x + opts.anchorOffsetX) / gridSize;
      final yCenter = (y + opts.anchorOffsetY) / gridSize;
      
      // Usar scale=1.0 y aspect_ratio=1.0 como en el modelo
      final w = 1.0;
      final h = 1.0;

      anchors.add(Anchor(xCenter, yCenter, w, h));
    }
  }

  print('✅ Anclas generadas: ${anchors.length}');
  return anchors;
}

AnchorOption getFullRangeOptions() {
  return AnchorOption(
    numLayers: 1,
    inputSizeWidth: 192,
    inputSizeHeight: 192,
    anchorOffsetX: 0.5,
    anchorOffsetY: 0.5,
    strides: [4],
    interpolatedScaleAspectRatio: 0.0,
  );
}

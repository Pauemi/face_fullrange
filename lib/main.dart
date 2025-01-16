import 'dart:io';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'evaluation/face_detection_test.dart';
import 'homepage.dart';
import 'utils/global_key.dart';

void main() {
  runApp(const FaceDetectionML());
}

class FaceDetectionML extends StatelessWidget {
  const FaceDetectionML({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Prototipo Detección Facial',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      debugShowCheckedModeBanner: false,
      home: const MainScreen(), // Establecer la pantalla principal
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final List<Map<String, String>> slides = const [
    {
      'image': 'assets/carousel/facial_detection_image.webp',
      'title': 'Reconocimiento Facial',
      'text': 'Implementación de la solución de detección facial',
    },
    {
      'image': 'assets/carousel/machinelearning.webp',
      'title': 'Aprendizaje Automático',
      'text': 'Prototipo de implementación de ML en dispositivos móviles',
    },
    {
      'image': 'assets/carousel/mlkit.jpg',
      'title': 'Google ML Kit',
      'text': 'Implementación del kit de aprendizaje automático de Google',
    },
  ];

  final CarouselSliderController _controller = CarouselSliderController();

  int _currentIndex = 0;

  Future<String> _getResultsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final resultsDir = Directory('${directory.path}/results');
    if (!await resultsDir.exists()) {
      await resultsDir.create(recursive: true);
    }
    return resultsDir.path;
  }

  Future<void> requestStoragePermission() async {
    print('📱 Solicitando permisos de almacenamiento...');

    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isGranted) {
        print('✅ Permiso de gestión de almacenamiento ya otorgado.');
        return;
      }

      var status = await Permission.manageExternalStorage.status;
      print('   Estado inicial: $status');

      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
        print('   Estado después de solicitud: $status');

        if (!status.isGranted) {
          throw Exception('❌ Se requiere permiso de gestión de almacenamiento.');
        }
      }

      print('✅ Permiso de gestión de almacenamiento otorgado.');
    } else if (Platform.isIOS) {
      // Manejar permisos para iOS si es necesario
      var status = await Permission.photos.status;
      if (!status.isGranted) {
        status = await Permission.photos.request();
        if (!status.isGranted) {
          throw Exception('❌ Se requiere permiso de fotos.');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: const Text(
          'Prototipo Multiplataforma',
          style: TextStyle(
            fontSize: 26,
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CarouselSlider(
              options: CarouselOptions(
                height: 400.0,
                autoPlay: false,
                enlargeCenterPage: true,
                onPageChanged: (index, reason) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
              ),
              items: slides.map((slide) {
                return Builder(
                  builder: (BuildContext context) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: MediaQuery.of(context).size.width,
                          margin: const EdgeInsets.symmetric(horizontal: 5.0),
                          child: Image.asset(
                            slide['image']!,
                            fit: BoxFit.contain,
                            height: 270,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          slide['title']!,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          slide['text']!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    );
                  },
                );
              }).toList(),
              carouselController: _controller,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: slides.asMap().entries.map((entry) {
                return GestureDetector(
                  onTap: () {
                    _controller.animateToPage(
                      entry.key,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                    setState(() {
                      _currentIndex = entry.key;
                    });
                  },
                  child: Container(
                    width: 12.0,
                    height: 12.0,
                    margin: const EdgeInsets.symmetric(
                        vertical: 8.0, horizontal: 4.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_currentIndex == entry.key
                          ? Colors.green
                          : Colors.grey),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const HomePage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightGreen,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    shadowColor: Colors.black.withOpacity(0.5),
                    elevation: 5,
                  ),
                  child: const Text(
                    'Ingresar',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final tester = FaceDetectorTest(
                        datasetPath: 'assets/images/',
                        annotationsPath: 'assets/wider_face_val_bbx_gt.txt',
                        outputPath: await _getResultsDirectory(),
                      );
                      await tester.init();
                      await tester.runTest();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error en prueba: $e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    shadowColor: Colors.black.withOpacity(0.5),
                    elevation: 5,
                  ),
                  child: const Text(
                    'Ejecutar Prueba',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

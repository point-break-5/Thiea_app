import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:thiea_app/screens/cameraScreen/camera_screen.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Lock the app orientation to portrait
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    final List<CameraDescription> cameras = await availableCameras();

    if (cameras.isEmpty) {
      runApp(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Center(
              child: Text('No cameras found on this device'),
            ),
          ),
        ),
      );
      return;
    }

    runApp(
      MaterialApp(
        theme: ThemeData.dark(),
        debugShowCheckedModeBanner: false,
        home: CameraScreen(cameras: cameras),
      ),
    );
  } catch (e) {
    print('Error initializing camera: $e');
    runApp(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: Text('Error initializing camera: $e'),
          ),
        ),
      ),
    );
  }
}

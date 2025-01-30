import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:thiea_app/screens/cameraScreen/camera_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'auth_controller.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Create a global variable to store cameras
late List<CameraDescription> cameras;

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    // Lock the app orientation to portrait
    await Supabase.initialize(
      url: 'https://knierfhicrdrzzeuzvve.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuaWVyZmhpY3Jkcnp6ZXV6dnZlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzY4MzMwNDcsImV4cCI6MjA1MjQwOTA0N30.DWK9iall-p5aLvdbaNPvwqflqaCEcvN37sHfFhtr-Uk',
    );
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    final List<CameraDescription> cameras = await availableCameras();
    Get.put(AuthController());

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

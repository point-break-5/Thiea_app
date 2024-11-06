import 'package:camera/camera.dart';

import './CommonHeader.dart';

import 'screens/camera_screen/camera_screen.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final cameras = await availableCameras();

    // if (cameras.isEmpty) {
    //   runApp(
    //     MaterialApp(
    //       debugShowCheckedModeBanner: false,
    //       theme: ThemeData.dark(),
    //       home: const Scaffold(
    //         body: Center(
    //           child: Text(
    //             'No cameras found on this device',
    //             style: TextStyle(color: Colors.white),
    //           ),
    //         ),
    //       ),
    //     ),
    //   );
    //   return;
    // }

    runApp(MyApp(cameras: cameras));
  } catch (e) {
    print('Error initializing camera: $e');
    runApp(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: Text(
              'Error initializing camera: $e',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        '/homeScreen': (context) => const HomeScreen(),
        '/homeScreen/aboutUs': (context) => AboutUs(),
        '/authWrapper': (context) => const AuthWrapper(),
        '/authWrapper/logIn': (context) => const Login(),
        '/authWrapper/signUp': (context) => const Signup(),
      },
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: CameraScreen(cameras: cameras),
    );
  }
}

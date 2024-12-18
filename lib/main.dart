import 'package:flutter/material.dart';
import './photo_gallery_page.dart';
import 'cameraHomePage.dart';
import 'package:flutter/services.dart';


Future<void> main() async{
  // Set the system navigation bar color to black
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.black, // Navigation bar color
      systemNavigationBarIconBrightness: Brightness.light, // Icon brightness
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Camera App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: CameraHomePage(),
    );
  }
}
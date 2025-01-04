import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:flutter/services.dart';

import 'features/gridPainter.dart';
import 'features/photoViewer.dart';
import 'package:image/image.dart' as img;

import 'package:geolocator/geolocator.dart';
import 'package:gal/gal.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  late Future<void> _initializeControllerFuture;
  List<XFile> capturedImages = [];
  int selectedCamera = 0;
  FlashMode flashMode = FlashMode.off;
  bool isGridVisible = false;
  bool isFocusing = false;
  Offset? focusPoint;

  @override
  void initState() {
    super.initState();
    _initializeCamera(selectedCamera);
  }

  Future<void> _initializeCamera(int cameraIndex) async {
    try {
      final controller = CameraController(
        widget.cameras[cameraIndex],
        ResolutionPreset.max, // Set Resolution
        enableAudio: true,
      );

      _initializeControllerFuture = controller.initialize();
      await _initializeControllerFuture;

      if (mounted) {
        setState(() {
          _controller = controller;
          _controller?.setFlashMode(flashMode);
        });
      }
    } catch (e) {
      print('Error initializing camera controller: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing camera: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No additional cameras available'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_controller != null) {
      await _controller!.dispose();
    }

    selectedCamera = (selectedCamera + 1) % widget.cameras.length;
    await _initializeCamera(selectedCamera);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;

    try {
      final FlashMode nextMode = FlashMode.values[
          (FlashMode.values.indexOf(flashMode) + 1) % FlashMode.values.length];
      await _controller!.setFlashMode(nextMode);
      setState(() {
        flashMode = nextMode;
      });
    } catch (e) {
      print('Error toggling flash: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error toggling flash mode'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Camera not initialized'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      await _initializeControllerFuture;
      final XFile file = await _controller!.takePicture();

      // adding metadata to the image

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if(image == null){
        debugPrint('Failed to decode image');
        return;
      }

      final exifData = await readExifFromBytes(bytes);

      // print(file.saveTo('/storage/emulated/0/DCIM/Camera/')); // checking


      // saving to gallery

      try{
        await Gal.putImage(
          file.path,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image saved to ${file.path}'),
            duration: Duration(seconds: 2),
          ),
        );

        print('Image saved to gallery');
      } on Exception catch(e){
        print('Error saving image to gallery: $e');
      }

      // print(result); // checking

      // exifData['DateTime'] = DateTime.now().toString() as IfdTag;

      // exifData['Location'] = await Geolocator.getCurrentPosition().then((value) => value.toString()) as IfdTag;

      // exifData['Location'] = IfdTag(await Geolocator.getCurrentPosition().then((value) => value.toString()));

      print(exifData); // checking

      
      _showCaptureConfirmation();
    } catch (e) {
      print('Error taking picture: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error taking picture: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showCaptureConfirmation() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Photo captured!'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleFocusTap(TapDownDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final Size screenSize = MediaQuery.of(context).size;
    final Offset tapPosition = details.localPosition;
    final double x = tapPosition.dx / screenSize.width;
    final double y = tapPosition.dy / screenSize.height;

    setState(() {
      focusPoint = tapPosition;
      isFocusing = true;
    });

    _controller!.setFocusPoint(Offset(x, y));
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          isFocusing = false;
          focusPoint = null;
        });
      }
    });
  }

  Future<void> _deleteImage(int index) async {
    try {
      final XFile image = capturedImages[index];
      final File imageFile = File(image.path);

      if (await imageFile.exists()) {
        await imageFile.delete();
      }

      setState(() {
        capturedImages.removeAt(index);
      });
    } catch (e) {
      print('Error deleting image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting image: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Camera Controls Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row( // topbar optoins
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.grid_on),
                    color: isGridVisible ? Colors.yellow : Colors.white,
                    onPressed: () =>
                        setState(() => isGridVisible = !isGridVisible),
                  ),
                  IconButton(
                    icon: Icon(_getFlashIcon()),
                    color: flashMode == FlashMode.off
                        ? Colors.white
                        : Colors.yellow,
                    onPressed: _toggleFlash,
                  ),
                  // IconButton(
                  //   icon: const Icon(Icons.cameraswitch_outlined), 
                  //   onPressed: _switchCamera,
                  // ),
                ],
              ),
            ),

            
            // Camera Preview
            Expanded(
              flex: 3,
              child: FutureBuilder<void>(
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    if (_controller == null ||
                        !_controller!.value.isInitialized) {
                      return const Center(
                          child: Text('Camera not initialized'));
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          onTapDown: _handleFocusTap,
                          child: CameraPreview(_controller!),
                        ),
                        if (isGridVisible) _buildGrid(),
                        if (focusPoint != null && isFocusing)
                          _buildFocusPoint(),
                        // Positioned(
                        //   bottom: 20,
                        //   left: 0,
                        //   right: 0,
                        //   child: Row(
                        //     mainAxisAlignment: MainAxisAlignment.center,
                        //     children: [
                        //       FloatingActionButton(
                        //         heroTag: 'capture',
                        //         onPressed: _takePicture,
                        //         child: const Icon(Icons.camera, size: 36),
                        //       ),
                        //     ],
                        //   ),
                        // ),
                      ],
                    );
                  } else {
                    return const Center(child: CircularProgressIndicator());
                  }
                },
              ),
            ),

            // Bottom bar
            AnimatedContainer(duration: const Duration(milliseconds: 300),
              height: 100,

              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,

                children: [
                  IconButton( // gallery button
                    icon: Icon(Icons.image),
                    onPressed: (){
                      Navigator.pushNamed(context, '/galleryPreview');
                    },
                    color: Colors.white,
                  ),

                  IconButton(
                    icon: Icon(Icons.camera_alt), // camera button
                    onPressed: _takePicture,
                    color: Colors.white,
                    iconSize: 50,
                  ), // camera button

                  IconButton( // camera switch button
                    icon: Icon(Icons.cameraswitch_outlined), 
                    onPressed: _switchCamera,
                    color: Colors.white,
                  ),
                ],
              ),
            ),

            // // Gallery
            // Container(
            //   height: 120,
            //   color: Colors.black87,
            //   child: capturedImages.isEmpty
            //       ? const Center(
            //           child: Text(
            //             'No photos yet',
            //             style: TextStyle(color: Colors.white54),
            //           ),
            //         )
            //       : ListView.builder(
            //           scrollDirection: Axis.horizontal,
            //           itemCount: capturedImages.length,
            //           itemBuilder: (context, index) {
            //             return Padding(
            //               padding: const EdgeInsets.all(4.0),
            //               child: GestureDetector(
            //                 onTap: () {
            //                   Navigator.push(
            //                     context,
            //                     MaterialPageRoute(
            //                       builder: (context) => DisplayPictureScreen(
            //                         imagePath: capturedImages[index].path,
            //                         onDelete: () => _deleteImage(index),
            //                       ),
            //                     ),
            //                   );
            //                 },
            //                 child: Hero(
            //                   tag: capturedImages[index].path,
            //                   child: Container(
            //                     width: 100,
            //                     decoration: BoxDecoration(
            //                       border: Border.all(color: Colors.white24),
            //                       borderRadius: BorderRadius.circular(8),
            //                     ),
            //                     child: ClipRRect(
            //                       borderRadius: BorderRadius.circular(8),
            //                       child: Image.file(
            //                         File(capturedImages[index].path),
            //                         fit: BoxFit.cover,
            //                       ),
            //                     ),
            //                   ),
            //                 ),
            //               ),
            //             );
            //           },
            //         ),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: GridPainter(),
      ),
    );
  }

  Widget _buildFocusPoint() {
    return Positioned(
      left: focusPoint!.dx - 20,
      top: focusPoint!.dy - 20,
      child: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.yellow, width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  IconData _getFlashIcon() {
    switch (flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }
}

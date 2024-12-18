import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import 'dart:math' as math;

import './photo_gallery_page.dart';

class CameraHomePage extends StatefulWidget {
  const CameraHomePage({super.key});

  @override
  State<CameraHomePage> createState() => _CameraHomePageState();
}

class _CameraHomePageState extends State<CameraHomePage> with WidgetsBindingObserver {
  List<CameraDescription> cameras = [];
  CameraController? cameraController;
  int camera_index = 0;
  // late final previewSize;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // TODO: implement didChangeAppLifecycleState
    super.didChangeAppLifecycleState(state);
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController!.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (cameraController != null) {
        _setupCameraContoller();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _setupCameraContoller();
  }

  bool _isShutterPressed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70), //appBar height
        child: AppBar(
          
          elevation: 0.0,
          backgroundColor: Colors.black,
          actions: [
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.settings),
              color: Colors.white,
            )
          ],
          
          leading: IconButton(
            onPressed: () {},
            icon: Icon(Icons.flash_on),
            color: Colors.white,
          ),
        ),
      ),
      body: _buildUI(),
    );
  }

  Widget _buildUI() {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    return SafeArea(
      child: Container(
        color: Colors.black,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                // height: previewSize.height,
                // width: previewSize.width,
                child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(camera_index == 0?0: math.pi),
                    child: CameraPreview(cameraController!)),
              ),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Expanded(
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              child: Icon(
                Icons.photo_library,
                size: 40,
                color: Colors.white,
              ),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) {
                  return GalleryPage();
                }));
              },
            ),
            GestureDetector(
              child: Icon(
                Icons.camera,
                size: 80,
                color: _isShutterPressed ? Colors.grey : Colors.white,
              ),
              onTapDown: (_) {
                setState(() {
                  _isShutterPressed = true;
                });
              },
              onTapUp: (_) {
                setState(() {
                  _isShutterPressed = false;
                });
              },
              onTap: () async {
                XFile picture =
                    await cameraController!.takePicture(); // Take picture
                Gal.putImage(picture.path); // Save image to gallery
              },
            ),
            GestureDetector(
              child: Icon(
                Icons.flip_camera_ios,
                size: 40,
                color: Colors.white,
              ),
              onTap: () {
                setState(() {
                  camera_index = camera_index == 0 ? 1 : 0;
                  cameraController!.dispose();
                  cameraController =
                      CameraController(cameras[camera_index], ResolutionPreset.low);
                  cameraController!.initialize().then((_) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                  });
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setupCameraContoller() async {
    List<CameraDescription> _cameras = await availableCameras();
    // print(
    //     'Camera length ----------------->>>>>>>>>>>>>>>>>>>>>>>>> ${cameras.length}');
    // print(cameras);

    if (_cameras.isNotEmpty) {
      setState(() {
        cameras = _cameras;
        cameraController =
            CameraController(_cameras[2], ResolutionPreset.low);
        // previewSize = cameraController!.value.previewSize!;
      });
      cameraController!.initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {});
      });
    }
  }
}

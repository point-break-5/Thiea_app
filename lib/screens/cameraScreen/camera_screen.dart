import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:animations/animations.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:thiea_app/screens/galleryScreen/gallery_screen.dart' as gallery;
import 'cameraFeatures/grid_painter.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'dart:math' as math;
import 'package:thiea_app/models/photoMetadata.dart';
import 'package:thiea_app/models/location.dart';

part 'camera_screen_constants.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  DateTime? _recordingStartTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _requestLocationPermission();
    _initializeCamera(selectedCamera);
    await _loadSavedImages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera(selectedCamera);
    }
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_controller != null && _controller!.value.isInitialized)
              _buildCameraPreview()
            else
              const Center(child: CircularProgressIndicator()),
            Positioned(
              // top bar controls
              top: 0,
              left: 0,
              right: 0,
              child: _buildControls(),
            ),
            Positioned(
              // bottom bar controls
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.black54,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedToggleSwitch<bool>.dual(
                          current: isPhotoMode,
                          first: true,
                          second: false,
                          spacing: 20.0,
                          style: ToggleStyle(
                            backgroundColor: Colors.black45,
                            borderColor: Colors.white24,
                            borderRadius: BorderRadius.circular(20.0),
                            indicatorColor: Colors.blue,
                          ),
                          animationDuration: const Duration(milliseconds: 200),
                          onChanged: (mode) =>
                              setState(() => isPhotoMode = mode),
                          iconBuilder: (value) => Icon(
                            value ? Icons.camera_alt : Icons.videocam,
                            color: Colors.white,
                          ),
                          textBuilder: (value) => value
                              ? const Text('Photo',
                                  style: TextStyle(color: Colors.white))
                              : const Text('Video',
                                  style: TextStyle(color: Colors.white)),
                        ),
                        if (isVideoRecording) Row(
                            children: [
                            const SizedBox(width: 20),
                            StreamBuilder<int>(
                              stream: Stream.periodic(const Duration(seconds: 1), (count) => count),
                              builder: (context, snapshot) {
                                final startTime = _recordingStartTime ?? DateTime.now();
                                final duration = DateTime.now().difference(startTime);
                                final displayDuration = Duration(seconds: duration.inSeconds);
                                return Text(
                                  '${displayDuration.inMinutes.toString().padLeft(2, '0')}:${(displayDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 10,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildGalleryButton(),
                        _buildCaptureButton(),
                        _buildCameraSwitchButton(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  //.............................................................................................................................................
  Widget _buildCameraPreview() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onTapDown: (details) => _handleFocusTap(details),
      child: Stack(
        children: [
          Transform.scale(
            scale: 3.6 /
                _controller!.value.aspectRatio, // Doubled the scale factor
            child: Center(
              child: Transform.rotate(
                angle: _calculateRotationAngle(),
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
          ),
          if (isGridVisible) _buildGrid(),
          if (focusPoint != null && isFocusing) _buildFocusPoint(),
          if (isTimerActive) _buildTimerOverlay(),
        ],
      ),
    );
  }

  double _calculateRotationAngle() {
    final int sensorOrientation = _controller!.description.sensorOrientation;
    switch (sensorOrientation) {
      case 90:
        return math.pi / 2;
      case 270:
        return -math.pi / 2;
      case 180:
        return math.pi;
      default:
        return 0.0; // Default for 0 degrees
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null || _pointers != 2) {
      return;
    }

    _currentScale = (_baseScale * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom);

    await _controller!.setZoomLevel(_currentScale);
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
    _controller!.setExposurePoint(Offset(x, y));

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          isFocusing = false;
          focusPoint = null;
        });
      }
    });
  }

  Widget _buildGrid() {
    return CustomPaint(
      painter: GridPainter(),
      size: Size.infinite,
    );
  }

  Widget _buildTimerOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Text(
          '$selectedTimer',
          style: const TextStyle(
            fontSize: 72,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
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

  //.............................................................................................................................................
  Widget _buildControls() {
    return Container(
      color: Colors.black54,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                // grid toggle button
                icon: Icon(
                  isGridVisible ? Icons.grid_on : Icons.grid_off,
                  color: Colors.white,
                ),
                onPressed: () => setState(() => isGridVisible = !isGridVisible),
              ),
              IconButton(
                // flash button
                icon: Icon(
                  _getFlashIcon(),
                  color: Colors.white,
                ),
                onPressed: _toggleFlash,
              ),
              IconButton(
                // ISO button
                icon: Icon(
                  exposureMode == ExposureMode.auto
                      ? Icons.exposure
                      : Icons.exposure_plus_1,
                  color: Colors.white,
                ),
                onPressed: _toggleExposureMode,
              ),
              IconButton(
                // focus mode button
                icon: Icon(
                  focusMode == FocusMode.auto
                      ? Icons.filter_center_focus
                      : Icons.center_focus_strong,
                  color: Colors.white,
                ),
                onPressed: _toggleFocusMode,
              ),
            ],
          ),
          if (exposureMode == ExposureMode.locked) _buildExposureControl(),
        ],
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
      default:
        return Icons.flash_off;
    }
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

  Future<void> _toggleExposureMode() async {
    if (_controller == null) return;

    try {
      final ExposureMode newMode = exposureMode == ExposureMode.auto
          ? ExposureMode.locked
          : ExposureMode.auto;
      await _controller!.setExposureMode(newMode);
      setState(() {
        exposureMode = newMode;
      });
    } catch (e) {
      print('Error toggling exposure mode: $e');
    }
  }

  Future<void> _toggleFocusMode() async {
    if (_controller == null) return;

    try {
      final FocusMode newMode =
          focusMode == FocusMode.auto ? FocusMode.locked : FocusMode.auto;
      await _controller!.setFocusMode(newMode);
      setState(() {
        focusMode = newMode;
      });
    } catch (e) {
      print('Error toggling focus mode: $e');
    }
  }

  Widget _buildExposureControl() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Removed unrelated ListTiles (Share, Info, Delete)
          // Added Exposure controls
          Text(
            'Exposure: ${_currentExposureOffset.toStringAsFixed(1)}',
            style: const TextStyle(color: Colors.white),
          ),
          Slider(
            value: _currentExposureOffset,
            min: _minAvailableExposureOffset,
            max: _maxAvailableExposureOffset,
            onChanged: (double value) async {
              setState(() {
                _currentExposureOffset = value;
              });
              await _controller?.setExposureOffset(value);
            },
          ),
        ],
      ),
    );
  }

  //.............................................................................................................................................
  Widget _buildGalleryButton() {
    return OpenContainer(
      transitionDuration: const Duration(milliseconds: 500),
      transitionType: ContainerTransitionType.fadeThrough,
      openBuilder: (context, _) {
        // Create a snapshot of the images to avoid direct iteration
        final imagesSnapshot = List<XFile>.from(capturedImages);
        return gallery.GalleryScreen(
          images: imagesSnapshot,
          onDelete: _deleteImage,
          onShare: _shareImage,
          onInfo: _showImageInfo,
        );
      },
      closedElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(40),
      ),
      openShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(0),
      ),
      closedColor: Colors.transparent,
      openColor: Colors.white,
      closedBuilder: (context, openContainer) {
        return GestureDetector(
          onTap: isTimerActive ? null : openContainer,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white),
              image: capturedImages.isNotEmpty
                  ? DecorationImage(
                      image: FileImage(File(capturedImages.first.path)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: capturedImages.isEmpty
                ? const Icon(Icons.photo_library, color: Colors.white)
                : null,
          ),
        );
      },
    );
  }
  // Widget _buildGalleryButton() {
  //   return GestureDetector(
  //     onTap: () => _showGallery(context),
  //     child: Container(
  //       width: 60,
  //       height: 60,
  //       decoration: BoxDecoration(
  //         shape: BoxShape.circle,
  //         border: Border.all(color: Colors.white),
  //         image: capturedImages.isNotEmpty
  //             ? DecorationImage(
  //                 image: FileImage(File(capturedImages.first.path)),
  //                 fit: BoxFit.cover,
  //               )
  //             : null,
  //       ),
  //       child: capturedImages.isEmpty
  //           ? const Icon(Icons.photo_library, color: Colors.white)
  //           : null,
  //     ),
  //   );
  // }

  void _showGallery(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => gallery.GalleryScreen(
          images: capturedImages,
          onDelete: _deleteImage,
          onShare: _shareImage,
          onInfo: _showImageInfo,
        ),
      ),
    );
  }

  Future<void> _deleteImage(int index) async {
    try {
      final file = File(capturedImages[index].path);
      if (await file.exists()) {
        await file.delete();
        await _deleteMetadata(capturedImages[index].path);
        setState(() {
          capturedImages.removeAt(index);
        });
        _loadSavedImages();
      }
    } catch (e) {
      print('Error deleting image: $e');
    }
  }

  Future<void> _loadSavedImages() async {
    try {
      final String dirPath = await _localPath;
      final Directory dir = Directory(dirPath);

      if (!await dir.exists()) {
        return;
      }

      final List<FileSystemEntity> files = await dir
          .list()
          .where((entity) =>
              entity is File &&
              ['.jpg', '.jpeg', '.png']
                  .contains(path.extension(entity.path).toLowerCase()))
          .toList();

      final List<XFile> loadedImages = files
          .map((file) => XFile(file.path))
          .toList()
        ..sort((a, b) => File(b.path)
            .lastModifiedSync()
            .compareTo(File(a.path).lastModifiedSync()));

      if (mounted) {
        setState(() {
          capturedImages = loadedImages;
        });
      }
    } catch (e) {
      print('Error loading saved images: $e');
    }
  }

  Future<String> get _localPath async {
    final directory = await getExternalStorageDirectory();
    final String folderPath = '${directory!.path}/$appFolderName';
    final Directory folder = Directory(folderPath);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folderPath;
  }

  Future<void> _deleteMetadata(String imagePath) async {
    try {
      final directory = await getExternalStorageDirectory();
      final String metadataPath =
          '${directory!.path}/$appFolderName/metadata.json';
      final file = File(metadataPath);

      if (await file.exists()) {
        final String contents = await file.readAsString();
        final List<dynamic> jsonList = json.decode(contents);
        final updatedMetadata =
            jsonList.where((item) => item['path'] != imagePath).toList();
        await file.writeAsString(json.encode(updatedMetadata));
      }
    } catch (e) {
      print('Error deleting metadata: $e');
    }
  }

  Future<void> _shareImage(String imagePath) async {
    try {
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: 'Check out this photo!',
      );
    } catch (e) {
      print('Error sharing image: $e');
    }
  }

  Future<void> _showImageInfo(String imagePath) async {
    try {
      final String dirPath = await _localPath;
      final String metadataPath = '$dirPath/metadata.json';
      final file = File(metadataPath);

      if (await file.exists()) {
        final String contents = await file.readAsString();
        final List<dynamic> jsonList = json.decode(contents);
        final metadata = jsonList.firstWhere(
          (item) => item['path'] == imagePath,
          orElse: () => null,
        );

        if (metadata != null && mounted) {
          final photoMetadata = PhotoMetadata.fromJson(metadata);
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Image Information'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Date: ${DateFormat('MMM d, yyyy HH:mm').format(photoMetadata.dateTime)}'),
                  if (photoMetadata.placeName != null)
                    Text('Location: ${photoMetadata.placeName}'),
                  Text('Path: ${photoMetadata.path}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      print('Error showing image info: $e');
    }
  }

  //.............................................................................................................................................
  bool isPressed = false;

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          isPressed = true;
        });
      },
      onTapUp: (_) {
        setState(() {
          isPressed = false;
        });
        if (isPhotoMode) {
          if (!isTimerActive) {
            _takePictureWithTimer();
          }
        } else {
          // implementing video capture functionalities

          if (isVideoRecording) {
            setState(() {
              isVideoRecording = false;
            });
            _stopRecordingVideoAndSave();
          } else {
            setState(() {
              isVideoRecording = true;
            });
            _startRecordingVideo();
          }
        }
      },
      onTapCancel: () {
        setState(() {
          isPressed = false;
        });
      },
      child: AnimatedContainer(
        duration: Duration(microseconds: 2000),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: 4,
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: EdgeInsets.all(isPressed ? 10 : 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (isPhotoMode ? Colors.white : Colors.red),
          ),
          child: isVideoRecording
              ? Center(
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Future<void> _startRecordingVideo() async {
    try {
      setState(() {
        isVideoRecording = true;
        _recordingStartTime = DateTime.now(); // Start the timer here
      });
      await _controller!.startVideoRecording();
    } catch (e) {
      print('Error starting video recording: $e');
    }
  }

  Future<void> _stopRecordingVideoAndSave() async {
    try {
      final XFile? videoFile = await _controller!.stopVideoRecording();
      setState(() {
        isVideoRecording = false;
        _recordingStartTime = null; // Reset the timer here
      });
      // Handle the saved video file here
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String dirPath = await _localPath;
      final String filePath = '$dirPath/VID_$timestamp.mp4';
      videoFile?.saveTo(filePath);

    } catch (e) {
      print('Error stopping video recording: $e');
    }
  }
  // Widget _buildCaptureButton() {
  //   return GestureDetector(
  //     onTap: isTimerActive ? null : _takePictureWithTimer,
  //     child: Container(
  //       width: 80,
  //       height: 80,
  //       decoration: BoxDecoration(
  //         shape: BoxShape.circle,
  //         border: Border.all(
  //           color: Colors.white,
  //           width: 4,
  //         ),
  //       ),
  //       child: Container(
  //         decoration: const BoxDecoration(
  //           shape: BoxShape.circle,
  //           color: Colors.white,
  //         ),
  //         margin: const EdgeInsets.all(8),
  //       ),
  //     ),
  //   );
  // }

  Future<void> _takePictureWithTimer() async {
    if (selectedTimer == null || selectedTimer == 0) {
      await _takePicture();
      return;
    }

    setState(() {
      isTimerActive = true;
    });

    for (int i = selectedTimer!; i > 0; i--) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Taking picture in $i...'),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await Future.delayed(const Duration(seconds: 1));
    }

    if (mounted) {
      setState(() {
        isTimerActive = false;
      });
      await _takePicture();
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Camera not initialized')),
      );
      return;
    }

    try {
      final XFile originalImage = await _controller!.takePicture();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String dirPath = await _localPath;
      final String filePath = '$dirPath/IMG_$timestamp.jpg';

      await originalImage.saveTo(filePath);

      setState(() {
        capturedImages.insert(0, XFile(filePath));
      });

      _showCaptureConfirmation();
      _preprocessPhoto(filePath);
    } catch (e) {
      print('Error taking picture: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error taking picture: $e')),
      );
    }
  }

  void _showCaptureConfirmation() {
    OverlayEntry? overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Container(
        color: Colors.white.withOpacity(0.7),
      ),
    );

    Overlay.of(context)?.insert(overlayEntry);

    Future.delayed(const Duration(milliseconds: 100), () {
      overlayEntry?.remove();
    });
  }

  Future<void> _preprocessPhoto(String filePath) async {
    try {
      final location = await _getCurrentLocation();
      String? placeName;
      String? subLocality;
      if (location != null) {
        placeName = await _getPlaceName(location);
        subLocality = await _getSubLocality(location);
      }
      final metadata = PhotoMetadata(
        path: filePath,
        dateTime: DateTime.now(),
        location: location,
        placeName: placeName,
        subLocality: subLocality,
      );
      await _saveMetadata(metadata);
    } catch (e) {
      print('Error preprocessing photo: $e');
    }
  }

  Future<Location?> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return Location(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  Future<String?> _getPlaceName(Location location) async {
    try {
      List<geocoding.Placemark> placemarks =
          await geocoding.placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        geocoding.Placemark place = placemarks.first;
        //print(place);
        return '${place.locality}, ${place.country}';
      }
    } catch (e) {
      print('Error getting place name: $e');
    }
    return null;
  }

  Future<String?> _getSubLocality(Location location) async {
    try {
      List<geocoding.Placemark> placemarks =
          await geocoding.placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        geocoding.Placemark place = placemarks.first;
        return '${place.name}, ${place.street}, ${place.subLocality}, ${place.postalCode}';
      }
    } catch (e) {
      print('Error getting sublocality name: $e');
    }
    return null;
  }

  Future<void> _saveMetadata(PhotoMetadata metadata) async {
    try {
      final directory = await getExternalStorageDirectory();
      final String metadataPath =
          '${directory!.path}/MyCameraApp/metadata.json';
      final metadataFile = File(metadataPath);

      List<Map<String, dynamic>> existingMetadata = [];
      if (await metadataFile.exists()) {
        final String content = await metadataFile.readAsString();
        existingMetadata = List<Map<String, dynamic>>.from(
          json.decode(content),
        );
      }

      existingMetadata.add(metadata.toJson());
      await metadataFile.writeAsString(json.encode(existingMetadata));
    } catch (e) {
      print('Error saving metadata: $e');
    }
  }

  //.............................................................................................................................................
  Widget _buildCameraSwitchButton() {
    return GestureDetector(
      onTap: _switchCamera,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white),
        ),
        child: const Icon(
          Icons.flip_camera_ios,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }

  void _switchCamera() async {
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

    final newCameraIndex = (selectedCamera + 1) % widget.cameras.length;

    await _initializeCamera(newCameraIndex);
    setState(() {
      selectedCamera = newCameraIndex;
    });
  }

  Future<void> _initializeCamera(int cameraIndex) async {
    try {
      final controller = CameraController(
        widget.cameras[cameraIndex],
        ResolutionPreset.max,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _initializeControllerFuture = controller.initialize().then((_) async {
        if (mounted) {
          await Future.wait([
            controller
                .getMinExposureOffset()
                .then((value) => _minAvailableExposureOffset = value),
            controller
                .getMaxExposureOffset()
                .then((value) => _maxAvailableExposureOffset = value),
            controller
                .getMaxZoomLevel()
                .then((value) => _maxAvailableZoom = value),
            controller
                .getMinZoomLevel()
                .then((value) => _minAvailableZoom = value),
          ]);

          setState(() {
            _controller = controller;
            _controller?.setFlashMode(flashMode);
            _isCameraAvailable = true;
          });
        }
      });

      await _initializeControllerFuture;
    } catch (e) {
      print('Error initializing camera: $e');
      setState(() {
        _isCameraAvailable = false;
      });
    }
  }

  // void _readMeta() async {
  //   try {
  //     // Get the directory path
  //     final String dirPath = await _localPath;
  //     final metadataFile = File('$dirPath/metadata.json');
  //     // Initialize metadata list
  //     List<Map<String, dynamic>> existingMetadata = [];
  //     // Check if the metadata file exists
  //     if (await metadataFile.exists()) {
  //       // Read and parse the metadata file
  //       final String content = await metadataFile.readAsString();
  //       existingMetadata =
  //           List<Map<String, dynamic>>.from(json.decode(content));
  //     }
  //     // Process metadata to extract location and other fields
  //     for (var meta in existingMetadata) {
  //       if (meta.containsKey('location') && meta['location'] != null) {
  //         final location = meta['location'];
  //         final double latitude = location['latitude'];
  //         final double longitude = location['longitude'];
  //         final String name = meta['placeName'];
  //         print('Location: Latitude $latitude, Longitude $longitude, Name: $name');
  //       } else {
  //         print('No location data available for this metadata entry.');
  //       }
  //     }
  //   } catch (e) {
  //     print('Error reading metadata: $e');
  //   }
  // }
}

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:untitled/screens/gallery_screen.dart';
// Data Models
class PhotoMetadata {
  final String path;
  final DateTime dateTime;
  final Location? location;
  final String? placeName;
  final String? filter;
  final List<FaceData>? faces;

  PhotoMetadata({
    required this.path,
    required this.dateTime,
    this.location,
    this.placeName,
    this.filter,
    this.faces,
  });

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'dateTime': dateTime.toIso8601String(),
      'location': location?.toJson(),
      'placeName': placeName,
      'filter': filter,
      'faces': faces?.map((face) => face.toJson()).toList(),
    };
  }

  static PhotoMetadata fromJson(Map<String, dynamic> json) {
    return PhotoMetadata(
      path: json['path'],
      dateTime: DateTime.parse(json['dateTime']),
      location: json['location'] != null ? Location.fromJson(json['location']) : null,
      placeName: json['placeName'],
      filter: json['filter'],
      faces: json['faces'] != null
          ? (json['faces'] as List).map((f) => FaceData.fromJson(f)).toList()
          : null,
    );
  }
}

class Location {
  final double latitude;
  final double longitude;

  Location({required this.latitude, required this.longitude});

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  static Location fromJson(Map<String, dynamic> json) {
    return Location(
      latitude: json['latitude'],
      longitude: json['longitude'],
    );
  }
}

class FaceData {
  final Rect boundingBox;
  final double? smilingProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;

  FaceData({
    required this.boundingBox,
    this.smilingProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
  });

  Map<String, dynamic> toJson() {
    return {
      'boundingBox': {
        'left': boundingBox.left,
        'top': boundingBox.top,
        'right': boundingBox.right,
        'bottom': boundingBox.bottom,
      },
      'smilingProbability': smilingProbability,
      'leftEyeOpenProbability': leftEyeOpenProbability,
      'rightEyeOpenProbability': rightEyeOpenProbability,
    };
  }

  static FaceData fromJson(Map<String, dynamic> json) {
    final box = json['boundingBox'];
    return FaceData(
      boundingBox: Rect.fromLTRB(
        box['left'],
        box['top'],
        box['right'],
        box['bottom'],
      ),
      smilingProbability: json['smilingProbability'],
      leftEyeOpenProbability: json['leftEyeOpenProbability'],
      rightEyeOpenProbability: json['rightEyeOpenProbability'],
    );
  }
}

// Main Camera App
class CameraApp extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraApp({Key? key, required this.cameras}) : super(key: key);

  @override
  _CameraAppState createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> with WidgetsBindingObserver {
  CameraController? _controller;
  late Future<void> _initializeControllerFuture;
  List<XFile> capturedImages = [];
  int selectedCamera = 0;
  FlashMode flashMode = FlashMode.off;
  bool isGridVisible = false;
  bool isFocusing = false;
  Offset? focusPoint;
  int? selectedTimer;
  bool isTimerActive = false;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;
  double _minAvailableExposureOffset = 0.0;
  double _maxAvailableExposureOffset = 0.0;
  double _currentExposureOffset = 0.0;
  bool _isCameraAvailable = true;
  int _pointers = 0;
  ExposureMode exposureMode = ExposureMode.auto;
  FocusMode focusMode = FocusMode.auto;
  final String appFolderName = 'MyCameraApp';

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

  Future<void> _initializeCamera(int cameraIndex) async {
    try {
      final controller = CameraController(
        widget.cameras[cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _initializeControllerFuture = controller.initialize().then((_) async {
        if (mounted) {
          await Future.wait([
            controller.getMinExposureOffset().then(
                    (value) => _minAvailableExposureOffset = value),
            controller.getMaxExposureOffset().then(
                    (value) => _maxAvailableExposureOffset = value),
            controller.getMaxZoomLevel().then(
                    (value) => _maxAvailableZoom = value),
            controller.getMinZoomLevel().then(
                    (value) => _minAvailableZoom = value),
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

  Future<String> get _localPath async {
    final directory = await getExternalStorageDirectory();
    final String folderPath = '${directory!.path}/$appFolderName';
    final Directory folder = Directory(folderPath);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folderPath;
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
          ['.jpg', '.jpeg', '.png'].contains(
              path.extension(entity.path).toLowerCase()))
          .toList();

      final List<XFile> loadedImages = files
          .map((file) => XFile(file.path))
          .toList()
        ..sort((a, b) =>
            File(b.path).lastModifiedSync().compareTo(
                File(a.path).lastModifiedSync()));

      if (mounted) {
        setState(() {
          capturedImages = loadedImages;
        });
      }
    } catch (e) {
      print('Error loading saved images: $e');
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

    final Size screenSize = MediaQuery
        .of(context)
        .size;
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
      final String timestamp = DateTime
          .now()
          .millisecondsSinceEpoch
          .toString();
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

  Future<void> _preprocessPhoto(String filePath) async {
    try {
      final location = await _getCurrentLocation();
      String? placeName;
      if (location != null) {
        placeName = await _getPlaceName(location);
      }

      final metadata = PhotoMetadata(
        path: filePath,
        dateTime: DateTime.now(),
        location: location,
        placeName: placeName,
      );

      // Optionally, you can add face detection here using google_mlkit_face_detection

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
        return '${place.locality}, ${place.country}';
      }
    } catch (e) {
      print('Error getting place name: $e');
    }
    return null;
  }

  Future<void> _saveMetadata(PhotoMetadata metadata) async {
    try {
      final String dirPath = await _localPath;
      final metadataFile = File('$dirPath/metadata.json');

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

  Widget _buildCameraPreview() {
    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onTapDown: (details) => _handleFocusTap(details),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          if (isGridVisible) _buildGrid(),
          if (focusPoint != null && isFocusing) _buildFocusPoint(),
          if (isTimerActive) _buildTimerOverlay(),
        ],
      ),
    );
  }

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
                icon: Icon(
                  isGridVisible ? Icons.grid_on : Icons.grid_off,
                  color: Colors.white,
                ),
                onPressed: () => setState(() => isGridVisible = !isGridVisible),
              ),
              IconButton(
                icon: Icon(
                  _getFlashIcon(),
                  color: Colors.white,
                ),
                onPressed: _toggleFlash,
              ),
              IconButton(
                icon: Icon(
                  exposureMode == ExposureMode.auto
                      ? Icons.exposure
                      : Icons.exposure_plus_1,
                  color: Colors.white,
                ),
                onPressed: _toggleExposureMode,
              ),
              IconButton(
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
          if (exposureMode == ExposureMode.locked)
            _buildExposureControl(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_controller != null && _controller!.value.isInitialized)
              _buildCameraPreview()
            else
              const Center(child: CircularProgressIndicator()),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildControls(),
            ),

            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.black54,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildGalleryButton(),
                    _buildCaptureButton(),
                    _buildCameraSwitchButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryButton() {
    return GestureDetector(
      onTap: () => _showGallery(context),
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
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: isTimerActive ? null : _takePictureWithTimer,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: 4,
          ),
        ),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          margin: const EdgeInsets.all(8),
        ),
      ),
    );
  }

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

  void _showCaptureConfirmation() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Photo captured!'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
      final ExposureMode newMode =
      exposureMode == ExposureMode.auto ? ExposureMode.locked : ExposureMode
          .auto;
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

    final newCameraIndex = (selectedCamera + 1) % widget.cameras.length;

    await _initializeCamera(newCameraIndex);
    setState(() {
      selectedCamera = newCameraIndex;
    });
  }

  void _showGallery(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            GalleryScreen(
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

  Future<void> _deleteMetadata(String imagePath) async {
    try {
      final directory = await getExternalStorageDirectory();
      final String metadataPath = '${directory!
          .path}/$appFolderName/metadata.json';
      final file = File(metadataPath);

      if (await file.exists()) {
        final String contents = await file.readAsString();
        final List<dynamic> jsonList = json.decode(contents);
        final updatedMetadata = jsonList
            .where((item) => item['path'] != imagePath)
            .toList();
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
            builder: (context) =>
                AlertDialog(
                  title: const Text('Image Information'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Date: ${DateFormat('MMM d, yyyy HH:mm').format(
                          photoMetadata.dateTime)}'),
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

  Widget _buildGrid() {
    return CustomPaint(
      painter: GridPainter(),
      size: Size.infinite,
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
}

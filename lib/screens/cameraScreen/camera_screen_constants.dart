part of 'camera_screen.dart';

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
  final String appFolderName = 'MyCameraScreen';
  bool isPhotoMode = true;
  bool isVideoRecording = false;

  Timer? videoRecordingTimer;


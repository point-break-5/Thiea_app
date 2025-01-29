import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:thiea_app/screens/imagePreview/image_preview.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class DrawingScreen extends StatefulWidget {
  final String imagePath;
  final Function(String) onSave;

  const DrawingScreen({
    Key? key,
    required this.imagePath,
    required this.onSave,
  }) : super(key: key);

  @override
  _DrawingScreenState createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  List<List<Offset>> _strokes = []; // Changed from final to mutable
  List<Offset> _currentStroke = []; // Changed from final to mutable
  Color _selectedColor = Colors.red; // Default drawing color
  double _strokeWidth = 4.0; // Default stroke width

  
  Future<void> _saveDrawing() async {
    try {
      // Access the RepaintBoundary
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Unable to find render boundary.');
      }

      // Capture the image as a PNG
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Failed to convert image to byte data.');
      }
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Overwrite the existing image file
      final File file = File(widget.imagePath);
      await file.writeAsBytes(pngBytes);

      // Create updated image metadata
      final updatedImage = ImageWithMetadata(
        file: XFile(file.path),
        metadata: ImageMetadata(
          date: DateTime.now(), // Use current date for update
        ),
      );

      // Invoke the callback with the updated image
      widget.onSave(file.path);

      // Return the updated image to the parent for handling
      Navigator.pop(context, updatedImage); // Pop from Drawing Screen
      Navigator.pop(context, updatedImage); // Pop from Image Preview Screen
    } catch (e) {
      debugPrint('Error saving drawing: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save the drawing.')),
      );
    }
  }

  /// Removes the last stroke (undo functionality)
  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _strokes = List.from(_strokes)..removeLast();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to undo.')),
      );
    }
  }

  /// Clears all strokes (reset functionality)
  void _clear() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _strokes = [];
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to clear.')),
      );
    }
  }

  /// Opens color picker to select drawing color
  void _pickColor() async {
    Color selectedColor =
        _selectedColor; // Temporary variable to hold selected color

    Color? pickedColor = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: selectedColor,
            onColorChanged: (color) {
              selectedColor = color; // Update temporary variable
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(selectedColor),
            child: const Text('Select'),
          ),
        ],
      ),
    );

    if (pickedColor != null && pickedColor != _selectedColor) {
      setState(() {
        _selectedColor = pickedColor;
      });
    }
  }

  /// Opens stroke width selector
  void _pickStrokeWidth() async {
    double pickedWidth =
        _strokeWidth; // Temporary variable to hold selected width

    double? selectedWidth = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Stroke Width'),
        content: SizedBox(
          height: 100, // Constrain the height to prevent overly long dialog
          child: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  Slider(
                    value: pickedWidth,
                    min: 1.0,
                    max: 10.0,
                    divisions: 9,
                    label: pickedWidth.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        pickedWidth = value;
                      });
                    },
                  ),
                  Text('Width: ${pickedWidth.toStringAsFixed(1)}'),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(pickedWidth),
            child: const Text('Select'),
          ),
        ],
      ),
    );

    if (selectedWidth != null && selectedWidth != _strokeWidth) {
      setState(() {
        _strokeWidth = selectedWidth;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paint'),
        actions: [
          IconButton(
            onPressed: _undo,
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
          ),
          IconButton(
            onPressed: _clear,
            icon: const Icon(Icons.clear),
            tooltip: 'Clear All',
          ),
          IconButton(
            onPressed: _pickColor,
            icon: Icon(Icons.color_lens, color: _selectedColor),
            tooltip: 'Pick Color',
          ),
          IconButton(
            onPressed: _pickStrokeWidth,
            icon: const Icon(Icons.brush),
            tooltip: 'Stroke Width',
          ),
          IconButton(
            onPressed: _saveDrawing,
            icon: const Icon(Icons.save),
            tooltip: 'Save',
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _canvasKey,
        child: Stack(
          children: [
            // Base image
            Positioned.fill(
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.contain,
              ),
            ),
            // Drawing layer
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (details) {
                  RenderBox renderBox = _canvasKey.currentContext!
                      .findRenderObject() as RenderBox;
                  Offset localPosition =
                      renderBox.globalToLocal(details.globalPosition);
                  setState(() {
                    _currentStroke = [localPosition];
                    _strokes = List.from(_strokes)
                      ..add(List.from(_currentStroke));
                  });
                },
                onPanUpdate: (details) {
                  RenderBox renderBox = _canvasKey.currentContext!
                      .findRenderObject() as RenderBox;
                  Offset localPosition =
                      renderBox.globalToLocal(details.globalPosition);
                  setState(() {
                    _currentStroke.add(localPosition);
                    _strokes = List.from(_strokes)
                      ..removeLast()
                      ..add(List.from(_currentStroke));
                  });
                },
                onPanEnd: (_) {
                  setState(() {
                    _currentStroke = [];
                  });
                },
                child: CustomPaint(
                  painter: _DrawingPainter(
                    strokes: _strokes,
                    strokeColor: _selectedColor,
                    strokeWidth: _strokeWidth,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for drawing strokes
class _DrawingPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color strokeColor;
  final double strokeWidth;

  _DrawingPainter({
    required this.strokes,
    required this.strokeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var stroke in strokes) {
      if (stroke.length < 2)
        continue; // Need at least two points to draw a line
      Paint paint = Paint()
        ..color = strokeColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      for (int i = 0; i < stroke.length - 1; i++) {
        if (stroke[i] != null && stroke[i + 1] != null) {
          canvas.drawLine(stroke[i], stroke[i + 1], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

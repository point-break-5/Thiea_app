import 'package:flutter/material.dart';
import 'dart:io';
import 'package:intl/intl.dart';
//import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:exif/exif.dart';

class ImageWithDate {
  final XFile file;
  final DateTime date;

  ImageWithDate({required this.file, required this.date});
}

class ImageMetadata {
  final DateTime date;
  final String? location;
  final Map<String, String>? exifData;
  final String? caption;

  ImageMetadata({
    required this.date,
    this.location,
    this.exifData,
    this.caption,
  });
}

class ImageWithMetadata {
  final XFile file;
  final ImageMetadata metadata;

  ImageWithMetadata({required this.file, required this.metadata});
}

class ImagePreviewScreen extends StatefulWidget {
  final ImageWithMetadata image;
  final bool isFavorite;
  final Function(ImageWithMetadata) onImageUpdated;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const ImagePreviewScreen({
    Key? key,
    required this.image,
    required this.isFavorite,
    required this.onImageUpdated,
    required this.onFavoriteToggle,
    required this.onDelete,
    required this.onShare,
  }) : super(key: key);

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen>
    with SingleTickerProviderStateMixin {
  late PhotoViewController _photoViewController;
  late AnimationController _animationController;
  bool _isControlsVisible = true;
  double _verticalDrag = 0;
  bool _isEditing = false;
  String? _caption;
  File? _editedImage;
  final _captionController = TextEditingController();
  bool _isLoading = false;
  Map<String, String>? _exifData;

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController()
      ..outputStateStream.listen(_onViewStateChanged);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _caption = widget.image.metadata.caption;
    _captionController.text = _caption ?? '';
    _loadExifData();
  }

  Future<void> _loadExifData() async {
    try {
      final bytes = await File(widget.image.file.path).readAsBytes();
      final exifData = await readExifFromBytes(bytes);
      setState(() {
        _exifData = exifData
            .toString()
            .replaceAll('{', '') 
            .replaceAll('}', '')
            .split(',')
            .fold<Map<String, String>>({}, (map, item) {
          final parts = item.split(':');
          if (parts.length == 2) {
            map[parts[0].trim()] = parts[1].trim();
          }
          return map;
        });
      });
    } catch (e) {
      debugPrint('Error loading EXIF data: $e');
    }
  }

  void _onViewStateChanged(PhotoViewControllerValue value) {
    if (value.scale != null && value.scale == 1.0) {
      setState(() {
        _verticalDrag = 0;
      });
    }
  }

  Future<void> _applyFilter(String filterName) async {
    setState(() => _isLoading = true);
    try {
      final bytes = await File(widget.image.file.path).readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) throw Exception('Failed to decode image');

      img.Image filteredImage;
      switch (filterName) {
        case 'grayscale':
          filteredImage = img.grayscale(image);
          break;
        case 'sepia':
          filteredImage = img.sepia(image);
          break;
        case 'invert':
          filteredImage = img.invert(image);
          break;
        default:
          throw Exception('Unknown filter: $filterName');
      }

      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/filtered_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filteredFile = File(tempPath);
      await filteredFile.writeAsBytes(img.encodeJpg(filteredImage));

      setState(() {
        _editedImage = filteredFile;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error applying filter: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveEdits() async {
    if (_editedImage != null) {
      final newImage = ImageWithMetadata(
        file: XFile(_editedImage!.path),
        metadata: ImageMetadata(
          date: widget.image.metadata.date,
          location: widget.image.metadata.location,
          exifData: _exifData,
          caption: _captionController.text,
        ),
      );
      widget.onImageUpdated(newImage);
    }
    setState(() => _isEditing = false);
  }

  void _showEditingPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _captionController,
                    decoration: const InputDecoration(
                      labelText: 'Caption',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Filters',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildFilterOption('Original', null),
                      _buildFilterOption('Grayscale', 'grayscale'),
                      _buildFilterOption('Sepia', 'sepia'),
                      _buildFilterOption('Invert', 'invert'),
                    ],
                  ),
                ),
                if (_exifData != null) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'EXIF Data',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _exifData!.entries
                          .map((entry) => Chip(
                                label: Text('${entry.key}: ${entry.value}'),
                              ))
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: _saveEdits,
                    child: const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterOption(String name, String? filterName) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => filterName != null
                ? _applyFilter(filterName)
                : setState(() => _editedImage = null),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                border: Border.all(
                  color:
                      _isLoading ? Colors.grey : Theme.of(context).primaryColor,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.file(
                        File(widget.image.file.path),
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(name),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main image view
          GestureDetector(
            onTap: () =>
                setState(() => _isControlsVisible = !_isControlsVisible),
            child: PhotoView(
              controller: _photoViewController,
              imageProvider: _editedImage != null
                  ? FileImage(_editedImage!)
                  : FileImage(File(widget.image.file.path)),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              heroAttributes:
                  PhotoViewHeroAttributes(tag: widget.image.file.path),
            ),
          ),

          // Controls overlay
          AnimatedOpacity(
            opacity: _isControlsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Stack(
              children: [
                // Top bar
                _buildTopBar(),

                // Bottom bar
                _buildBottomBar(),
              ],
            ),
          ),

          // Loading indicator
          if (_isLoading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16,
          bottom: 16,
          left: 16,
          right: 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              color: Colors.white,
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('MMMM d, yyyy')
                        .format(widget.image.metadata.date),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis, // Prevent text overflow
                  ),
                  if (widget.image.metadata.location != null)
                    Text(
                      widget.image.metadata.location!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis, // Prevent text overflow
                    ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.share),
                  color: Colors.white,
                  onPressed: widget.onShare,
                ),
                IconButton(
                  icon: Icon(
                    widget.isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                  color: widget.isFavorite ? Colors.red : Colors.white,
                  onPressed: widget.onFavoriteToggle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
          left: 16,
          right: 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_caption != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _caption!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.share,
                    label: 'Share',
                    onTap: widget.onShare,
                  ),
                  _buildActionButton(
                    icon: widget.isFavorite
                        ? Icons.favorite
                        : Icons.favorite_border,
                    label: 'Favorite',
                    onTap: widget.onFavoriteToggle,
                    color: widget.isFavorite ? Colors.red : Colors.white,
                  ),
                  _buildActionButton(
                    icon: Icons.edit,
                    label: 'Edit',
                    onTap: _showEditingPanel,
                  ),
                  _buildActionButton(
                    icon: Icons.delete,
                    label: 'Delete',
                    onTap: () => widget.onDelete(),
                    color: Colors.red,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    _animationController.dispose();
    _captionController.dispose();
    super.dispose();
  }
}

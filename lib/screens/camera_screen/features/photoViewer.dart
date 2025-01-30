import 'package:flutter/material.dart';
// Removed duplicate import
import 'package:photo_view/photo_view.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class PhotoViewer extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;

  const PhotoViewer({
    Key? key,
    required this.assets,
    required this.initialIndex,
  }) : super(key: key);

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late PageController _pageController;
  Map<int, ChewieController> _videoControllers = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _initializeCurrentVideo(widget.initialIndex);
  }

  @override
  void dispose() {
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initializeCurrentVideo(int index) async {
    if (widget.assets[index].type == AssetType.video) {
      final file = await widget.assets[index].file;
      if (file != null) {
        final videoPlayerController = VideoPlayerController.file(file);
        await videoPlayerController.initialize();

        final chewieController = ChewieController(
          videoPlayerController: videoPlayerController,
          autoPlay: false,
          looping: false,
          aspectRatio: videoPlayerController.value.aspectRatio,
        );

        if (mounted) {
          setState(() {
            _videoControllers[index] = chewieController;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              _initializeCurrentVideo(index);
            },
            itemCount: widget.assets.length,
            itemBuilder: (context, index) {
              final asset = widget.assets[index];

              if (asset.type == AssetType.video) {
                if (_videoControllers.containsKey(index)) {
                  return Chewie(controller: _videoControllers[index]!);
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              } else {
                return FutureBuilder<Uint8List?>(
                  future: asset.originBytes,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return PhotoView(
                      imageProvider: MemoryImage(snapshot.data!),
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 2,
                    );
                  },
                );
              }
            },
          ),
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  // @override
  // Widget build(BuildContext context) {
  //   return Scaffold(
  //     backgroundColor: Colors.black,
  //     body: Stack(
  //       children: [
  //         PhotoViewGallery.builder(
  //           pageController: _pageController,
  //           itemCount: widget.assets.length,
  //           builder: (context, index) {
  //             return PhotoViewGalleryPageOptions.customChild(
  //               child: FutureBuilder<Uint8List?>(
  //                 future: widget.assets[index].originBytes,
  //                 builder: (context, snapshot) {
  //                   if (!snapshot.hasData) {
  //                     return const Center(child: CircularProgressIndicator());
  //                   }
  //                   return Image.memory(snapshot.data!);
  //                 },
  //               ),
  //               minScale: PhotoViewComputedScale.contained,
  //               maxScale: PhotoViewComputedScale.covered * 2,
  //             );
  //           },
  //         ),
  //         Positioned(
  //           top: 40,
  //           left: 10,
  //           child: IconButton(
  //             icon: const Icon(Icons.close, color: Colors.white),
  //             onPressed: () => Navigator.pop(context),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }
}

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:typed_data';

class GalleryPreview extends StatefulWidget {
  const GalleryPreview({Key? key}) : super(key: key);

  @override
  _GalleryPreviewState createState() => _GalleryPreviewState();
}

class _GalleryPreviewState extends State<GalleryPreview> {
  List<AssetEntity> assets = [];

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery() async {
    final permitted = await PhotoManager.requestPermissionExtend();
    if (permitted.isAuth) {
      final albums = await PhotoManager.getAssetPathList();
      if (albums.isNotEmpty) {
        final recentAlbum = albums.first;
        final recentAssets =
            await recentAlbum.getAssetListPaged(page: 0, size: 500);
        setState(() {
          assets = recentAssets;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Thiea Gallery'),
        backgroundColor: Color(0x44000000),
        centerTitle: true,
      ),
      body: assets.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3),
              itemCount: assets.length,
              itemBuilder: (context, index) {
                return Card(
                  child: FutureBuilder<Uint8List?>(
                    future: assets[index].thumbnailData,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          snapshot.hasData) {
                        return Container(
                          child: Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                          ),
                          // decoration: BoxDecoration(
                          //   image: DecorationImage(
                          //       image: MemoryImage(
                          //     snapshot.data!,
                          //     // scale:
                          //   )),
                          // ),
                        );
                      }
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                );
              },
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';

class GalleryPage extends StatefulWidget {
  @override
  _GalleryPageState createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<AssetEntity> photos = [];

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    // Request storage permission
    var status = await Permission.storage.request();
    if (status.isGranted) {
      // Fetch all images from the gallery
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );
      List<AssetEntity> allPhotos = await albums[0].getAssetListPaged(page: 0, size: 100); // Limit to 100 photos
      setState(() {
        photos = allPhotos;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Gallery")),
      body: photos.isNotEmpty
          ? GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, // Number of columns in the grid
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: photos.length,
              itemBuilder: (context, index) {
                return FutureBuilder<Uint8List?>(
                  future: photos[index].thumbnailData, // Load thumbnail
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done &&
                        snapshot.hasData) {
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                      );
                    }
                    return Center(child: CircularProgressIndicator());
                  },
                );
              },
            )
          : Center(child: Text("No photos found")),
    );
  }
}

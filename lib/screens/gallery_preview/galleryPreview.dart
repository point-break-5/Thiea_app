import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';

class ImageGroup {
  final DateTime date;
  final List<AssetEntity> assets;

  ImageGroup(this.date, this.assets);
}

List<ImageGroup> _groupAssetsByDate(List<AssetEntity> assets) {
  // Sort assets by date
  final sorted = List<AssetEntity>.from(assets)
    ..sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

  // Group by date
  final groups = <DateTime, List<AssetEntity>>{};
  for (var asset in sorted) {
    final date = DateTime(
      asset.createDateTime.year,
      asset.createDateTime.month,
      asset.createDateTime.day,
    );
    groups.putIfAbsent(date, () => []).add(asset);
  }

  return groups.entries.map((e) => ImageGroup(e.key, e.value)).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
}

String _getFormattedDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final inputDate = DateTime(date.year, date.month, date.day);

  if (inputDate == today) {
    return 'Today';
  } else if (inputDate == yesterday) {
    return 'Yesterday';
  } else {
    return DateFormat('MMM d, yyyy').format(date);
  }
}

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
    final groups = _groupAssetsByDate(assets);

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,

      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text(
          'Thiea Gallery',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Color(0x44000000),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              // need to implement account login/signup logic
            },
            icon: const Icon(Icons.account_circle),
          ),
        ],
      ),

      body: Container(
        color: Colors.grey[900],
        child: ListView.builder(
          itemCount: groups.length,
          itemBuilder: (context, groupIndex) {
            final group = groups[groupIndex];
            return Container(
              margin: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      _getFormattedDate(group.date),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: group.assets.length,
                    itemBuilder: (context, index) {
                      final asset = group.assets[index];
                      return Container(
                        padding: const EdgeInsets.all(3),
                        child: FutureBuilder<Uint8List?>(
                          future: asset.thumbnailData,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.done &&
                                snapshot.hasData) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                ),
                              );
                            }
                            return const Center(
                                child: CircularProgressIndicator());
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),

      // body: assets.isEmpty
      //     ? const Center(child: CircularProgressIndicator())
      //     : Container(
      //         color: Colors.grey[900], // Background color
      //         child: GridView.builder(
      //           gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      //               crossAxisCount: 3),
      //           itemCount: assets.length,
      //           itemBuilder: (context, index) {
      //             return Container(
      //               margin: const EdgeInsets.all(5),
      //               child: FutureBuilder<Uint8List?>(
      //                 future: assets[index].thumbnailData,
      //                 builder: (context, snapshot) {
      //                   if (snapshot.connectionState == ConnectionState.done &&
      //                       snapshot.hasData) {
      //                     return ClipRRect(
      //                       borderRadius: BorderRadius.circular(10),
      //                       child: Image.memory(
      //                         snapshot.data!,
      //                         fit: BoxFit.cover,
      //                       ),
      //                     );
      //                   }
      //                   return const Center(child: CircularProgressIndicator());
      //                 },
      //               ),
      //             );
      //           },
      //         ),
      //       ),
      bottomNavigationBar: BottomAppBar(
          color: Color.fromARGB(150, 0, 0, 0),
          height: MediaQuery.of(context).size.height * 0.08,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.image),
                color: Colors.white,
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.home),
                color: Colors.white,
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.menu),
                color: Colors.white,
              ),
            ],
          ),
        )
    );

      
  }
}

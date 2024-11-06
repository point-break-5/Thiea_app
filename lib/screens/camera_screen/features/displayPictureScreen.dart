import 'dart:io';
import 'package:flutter/material.dart';

class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;
  final VoidCallback? onDelete;
 
  const DisplayPictureScreen({
    Key? key,
    required this.imagePath,
    this.onDelete,
  }) : super(key: key);
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                onDelete?.call();
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Center(
        child: Hero(
          tag: imagePath,
          child: Image.file(File(imagePath)),
        ),
      ),
    );
  }
}
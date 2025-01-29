import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class GalleryDatabase {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  static Future<Database> _initDb() async {
    final docsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = join(docsDirectory.path, 'my_gallery.db');

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS photos (
            Photo_ID INTEGER PRIMARY KEY AUTOINCREMENT,
            Photo_name TEXT,
            storage_path TEXT,
            isProcessed INTEGER,
            isFavorite INTEGER,
            location TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS faces (
            face_id INTEGER PRIMARY KEY,
            face_name TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS photo_faces (
            Photo_ID INTEGER,
            face_id INTEGER,
            PRIMARY KEY (Photo_ID, face_id)
          )
          ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS photo_online (
            online_id INTEGER PRIMARY KEY,
            photo_id INTEGER UNIQUE,
            FOREIGN KEY(photo_id) REFERENCES photos(Photo_ID)
          )
        ''');
      },
    );
  }

  static Future<void> insertPhoto({
    required String name,
    required String path,
    required bool processed,
    required bool favorite,
    required String location,
  }) async {
    final db = await database;
    await db.insert(
      'photos',
      {
        'Photo_name': name,
        'storage_path': path,
        'isProcessed': processed ? 1 : 0,
        'isFavorite': favorite ? 1 : 0,
        'location': location,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

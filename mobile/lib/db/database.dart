import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;

import '../models/meeting.dart';

/// Akses SQLite untuk riwayat meeting (lokal di perangkat).
class MeetingDatabase {
  MeetingDatabase._();
  static final MeetingDatabase instance = MeetingDatabase._();

  Database? _db;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<String> _dbPath() async {
    if (_isDesktop) {
      // sqflite mobile tidak jalan di desktop -> pakai implementasi FFI.
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await getApplicationSupportDirectory();
      return p.join(dir.path, 'notula.db');
    }
    return p.join(await getDatabasesPath(), 'notula.db');
  }

  Future<Database> _open() async {
    final path = await _dbPath();
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE meetings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            audio_path TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            transcript TEXT,
            summary TEXT,
            error TEXT,
            server_job_id TEXT,
            processing_seconds INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v2: simpan job_id server agar bisa resume polling setelah koneksi putus.
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE meetings ADD COLUMN server_job_id TEXT');
        }
        // v3: simpan lama proses konversi (detik).
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE meetings ADD COLUMN processing_seconds INTEGER');
        }
      },
    );
  }

  Future<List<Meeting>> getAll() async {
    final db = await _database;
    final rows = await db.query('meetings', orderBy: 'created_at DESC');
    return rows.map(Meeting.fromMap).toList();
  }

  Future<Meeting> insert(Meeting m) async {
    final db = await _database;
    final id = await db.insert('meetings', m.toMap()..remove('id'));
    return Meeting.fromMap({...m.toMap(), 'id': id});
  }

  Future<void> update(Meeting m) async {
    final db = await _database;
    await db.update('meetings', m.toMap(),
        where: 'id = ?', whereArgs: [m.id]);
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete('meetings', where: 'id = ?', whereArgs: [id]);
  }
}

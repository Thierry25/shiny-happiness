import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mynotes/extensions/list/filter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory, MissingPlatformDirectoryException;
import 'package:path/path.dart' show join;

import 'local_crud_exceptions.dart';

// const variables
const idColumn = 'id';
const emailColumn = 'email';
const userIdColumn = 'user_id';
const textColumn = 'text';
const isSyncedWithCloudColumn = 'is_synced_with_cloud';
const dbName = 'notes.db';
const noteTable = 'note';
const userTable = 'user';

const createUserTable = ''' CREATE TABLE IF NOT EXISTS "user" (
	      "id"	INTEGER NOT NULL,
	      "email"	TEXT NOT NULL UNIQUE,
	      PRIMARY KEY("id" AUTOINCREMENT)
      );''';

const createNoteTable = '''CREATE TABLE IF NOT EXISTS "note" (
	      "id"	INTEGER NOT NULL,
	      "user_id"	INTEGER NOT NULL,
	      "text"	TEXT,
	      "is_synced_with_cloud"	INTEGER NOT NULL DEFAULT 0,
	      PRIMARY KEY("id" AUTOINCREMENT),
	      FOREIGN KEY("user_id") REFERENCES "user"("id")
      );''';

// Service responsible to connect to our DB
class NotesService {
  Database? _db;

  List<DatabaseNote> _notes = [];

  DatabaseUser? _user;

  // Create singleton
  static final NotesService _shared = NotesService._sharedInstance();
  NotesService._sharedInstance() {
    _notesStreamController = StreamController<List<DatabaseNote>>.broadcast(
      onListen: () {
        _notesStreamController.sink.add(_notes);
      },
    );
  }
  factory NotesService() => _shared;

  late final StreamController<List<DatabaseNote>> _notesStreamController;

  Stream<List<DatabaseNote>> get allNotes =>
      _notesStreamController.stream.filter(
        (note) {
          final currentUser = _user;
          if (currentUser != null) {
            return note.userId == currentUser.id;
          }
          throw UserShouldBeSetBeforeReadingAllNotes();
        },
      );

  Future<DatabaseUser> getOrCreateUser({
    required String email,
    bool setAsCurrentUser = true,
  }) async {
    try {
      final user = await getUser(email: email);
      if (setAsCurrentUser) {
        _user = user;
      }
      return user;
    } on CouldNotFindUser {
      final createdUser = await createUser(email: email);
      if (setAsCurrentUser) {
        _user = createdUser;
      }
      return createdUser;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _cacheNotes() async {
    final allNotes = await getAllNotes();
    _notes = allNotes.toList();
    _notesStreamController.add(_notes);
  }

  Future<DatabaseNote> updateNote({
    required DatabaseNote note,
    required String text,
  }) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();

    await getNote(noteId: note.id);
    final updatesCount = await db.update(
      noteTable,
      {
        textColumn: text,
        isSyncedWithCloudColumn: 0,
      },
      where: 'id = ?',
      whereArgs: [note.id],
    );

    if (updatesCount == 0) throw CouldNotUpdateNote();
    final updatedNote = await getNote(noteId: note.id);
    _notes.removeWhere((note) => note.id == updatedNote.id);
    _notes.add(updatedNote);
    _notesStreamController.add(_notes);
    return updatedNote;
  }

  Future<List<DatabaseNote>> getAllNotes() async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final notes = await db.query(noteTable);

    return notes.map((n) => DatabaseNote.fromRow(n)).toList();
  }

  Future<DatabaseNote> getNote({required int noteId}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final results = await db.query(
      noteTable,
      limit: 1,
      where: 'id = ?',
      whereArgs: [noteId],
    );

    if (results.isEmpty) {
      throw CouldNotFindNote();
    }
    final note = DatabaseNote.fromRow(results.first);
    _notes.removeWhere((note) => note.id == noteId);
    _notes.add(note);
    _notesStreamController.add(_notes);
    return note;
  }

  Future<int> deleteAllNotes() async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final numberOfDeletions = await db.delete(noteTable);
    _notes = [];
    _notesStreamController.add(_notes);

    return numberOfDeletions;
  }

  Future<void> deleteNote({required int noteId}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final deletedCount = await db.delete(
      noteTable,
      where: '$idColumn = ?',
      whereArgs: [noteId],
    );

    if (deletedCount == 0) {
      throw CouldNotDeleteNote();
    }

    _notes.removeWhere((note) => note.id == noteId);
    _notesStreamController.add(_notes);
  }

  Future<DatabaseNote> createNote({required DatabaseUser owner}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();

    // make sure owner exists in the database with the correct id
    final dbUser = await getUser(email: owner.email);
    if (dbUser != owner) throw CouldNotFindUser();

    const text = '';
    final noteId = await db.insert(
      noteTable,
      {userIdColumn: owner.id, textColumn: text.toLowerCase()},
    );

    final note = DatabaseNote(
      id: noteId,
      userId: owner.id,
      text: text,
      isSyncedWithCloud: false,
    );

    _notes.add(note);
    _notesStreamController.add(_notes);
    return note;
  }

  Future<DatabaseUser> getUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final usersList = await db.query(
      userTable,
      limit: 1,
      where: '$emailColumn = ?',
      whereArgs: [email.toLowerCase()],
    );

    if (usersList.isEmpty) {
      throw CouldNotFindUser();
    } else {
      return DatabaseUser.fromRow(usersList.first);
    }
  }

  Future<DatabaseUser> createUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    // Verify that a user with the given email is not already saved
    final results = await db.query(
      userTable,
      limit: 1,
      where: '$emailColumn = ?',
      whereArgs: [email.toLowerCase()],
    );

    if (results.isNotEmpty) {
      throw UserAlreadyExists();
    }
    final userId =
        await db.insert(userTable, {emailColumn: email.toLowerCase()});
    return DatabaseUser(
      id: userId,
      email: email,
    );
  }

  Future<void> deleteUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final deletedCount = await db.delete(
      userTable,
      where: '$emailColumn = ?',
      whereArgs: [email.toLowerCase()],
    );
    if (deletedCount != 1) {
      throw CouldNotDeleteUser();
    }
  }

  Database _getDatabaseOrThrow() {
    final db = _db;
    if (db == null) {
      throw DatabaseIsNotOpen();
    } else {
      return db;
    }
  }

  Future<void> close() async {
    final db = _db;
    if (db == null) {
      throw DatabaseIsNotOpen();
    } else {
      await db.close();
      _db = null;
    }
  }

  Future<void> _ensureDbIsOpen() async {
    try {
      await open();
    } on DatabaseAlreadyOpenException {}
  }

  // Open connection with our DB
  Future<void> open() async {
    if (_db != null) throw DatabaseAlreadyOpenException();

    try {
      final docsPath = await getApplicationDocumentsDirectory();
      // ex: /android/data/docs/notes.db
      final dbPath = join(docsPath.path, dbName);
      final db = await openDatabase(dbPath);
      _db = db;

      // create user table
      await db.execute(createUserTable);
      // create note table
      await db.execute(createNoteTable);
      await _cacheNotes();
    } on MissingPlatformDirectoryException {
      throw UnableToGetDocumentsDirectory();
    }
  }
}

@immutable
class DatabaseUser {
  final int id;
  final String email;

  const DatabaseUser({
    required this.id,
    required this.email,
  });

  // All data(rows) in the sqlite table are saved as Map<String, Object?>
  // Provide a constructor to create a DatabaseUser instance based on this value
  DatabaseUser.fromRow(Map<String, Object?> map)
      : id = map[idColumn] as int,
        email = map[emailColumn] as String;

  @override
  String toString() => 'User, ID = $id, email = $email';

  @override
  bool operator ==(covariant DatabaseUser other) => id == other.id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class DatabaseNote {
  final int id;
  final int userId;
  final String text;
  final bool isSyncedWithCloud;

  const DatabaseNote({
    required this.id,
    required this.userId,
    required this.text,
    required this.isSyncedWithCloud,
  });

  DatabaseNote.fromRow(Map<String, Object?> map)
      : id = map[idColumn] as int,
        userId = map[userIdColumn] as int,
        text = map[textColumn] as String,
        isSyncedWithCloud = (map[isSyncedWithCloudColumn] as int) == 1;

  @override
  String toString() =>
      'Note, ID = $id, userId = $userId, isSyncedWithCloud = $isSyncedWithCloud';

  @override
  bool operator ==(covariant DatabaseNote other) => id == other.id;

  @override
  int get hashCode => id.hashCode;
}

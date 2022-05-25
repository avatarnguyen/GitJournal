import 'package:dart_git/utils/result.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/git_repo.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/note_storage.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:synchronized/synchronized.dart';
import 'package:universal_io/io.dart' as io;

class StorageException implements Exception {}

class ServerException implements Exception {}

class NoteUsecases {
  final GitNoteRepository gitRepo;

  NoteUsecases(this.gitRepo);

  final _gitOpLock = Lock();

  //**************** Add Note ****************
  Future<Result<Note>> addNote(Note note) async {
    final _noteAddedResult = await _addNoteToStorage(note);
    if (_noteAddedResult.isSuccess) {
      try {
        await _addNoteToGitRepo(note);
      } on StorageException catch (e) {
        Log.e('$e');
        return Result.fail(e);
      }
    }

    return _noteAddedResult;
  }

  Future<Result<Note>> _addNoteToStorage(Note note) async {
    note = note.updateModified();

    Result<Note> _storageResult = await saveNoteToStorage(note);
    if (_storageResult.isFailure) {
      Log.e(
        "Note saving failed",
        ex: _storageResult.error,
        stacktrace: _storageResult.stackTrace,
      );
      return fail(_storageResult);
    }
    note = _storageResult.getOrThrow();
    note.parent.add(note);
    return Result(note);
  }

  Future<Result<Note>> saveNoteToStorage(Note note) async {
    final _storageResult = await NoteStorage.save(note);
    return _storageResult;
  }

  Future<bool> _addNoteToGitRepo(Note note) async {
    try {
      return await _gitOpLock.synchronized(() async {
        Log.d("Got addNote lock");

        var result = await gitRepo.addNote(note);
        if (result.isFailure) {
          Log.e("addNote", result: result);
          return false;
        }
        return true;
      });
    } on Exception catch (e) {
      Log.e('$e');
      throw StorageException();
    }
  }

  //**************** Update Note ****************

  Future<Result<Note>> updateNote(Note note) async {
    final _noteAddedResult = await _updateStorageNote(note);
    if (_noteAddedResult.isSuccess) {
      try {
        await _updateGitNote(note);
      } on StorageException catch (e) {
        Log.e('$e');
        return Result.fail(e);
      }
    }

    return _noteAddedResult;
  }

  Future<Result<Note>> _updateStorageNote(Note note) async {
    note = note.updateModified();

    Result<Note> _storageResult = await saveNoteToStorage(note);
    if (_storageResult.isFailure) {
      Log.e(
        "Note saving failed",
        ex: _storageResult.error,
        stacktrace: _storageResult.stackTrace,
      );
      return fail(_storageResult);
    }
    note = _storageResult.getOrThrow();
    note.parent.updateNote(note);
    return Result(note);
  }

  Future<bool> _updateGitNote(Note note) async {
    try {
      return await _gitOpLock.synchronized(() async {
        Log.d("Got updateNote lock");

        var result = await gitRepo.updateNote(note);
        if (result.isFailure) {
          Log.e("addNote", result: result);
          return false;
        }
        return true;
      });
    } on Exception catch (e) {
      Log.e('$e');
      throw StorageException();
    }
  }

  //**************** Remove Note ****************

  Future<void> removeNotes(List<Note> notes) async {
    try {
      await _removeGitNotes(notes);
    } on ServerException catch (e) {
      Log.e('Remove Note Method: $e');
    }
  }

  Future<void> _removeGitNotes(List<Note> notes) async {
    try {
      return await _gitOpLock.synchronized(() async {
        Log.d("Got removeNote lock");

        var result = await gitRepo.removeNotes(notes);
        if (result.isFailure) {
          Log.e("remove Note failed", result: result);
          throw ServerException();
        }
      });
    } on Exception catch (e) {
      throw ServerException();
    }
  }

//**************** Undo Remove Note ****************

  Future<void> undoRemoveNote(Note note) async {
    try {
      await resetLastCommit().then((_) {
        note.parent.add(note);
      });
    } on ServerException catch (e) {
      Log.e('Remove Note Method: $e');
    }
  }

  Future<void> resetLastCommit() async {
    try {
      return await _gitOpLock.synchronized(() async {
        Log.d("Got undo remove note lock");

        var result = await gitRepo.resetLastCommit();
        if (result.isFailure) {
          Log.e("undoRemoveNote", result: result);
          throw ServerException();
        }
      });
    } on Exception catch (e) {
      throw ServerException();
    }
  }

//**************** Move Notes ****************

  Future<Result<List<Note>>> moveNotes(
    List<Note> notes,
    NotesFolderFS destFolder,
  ) async {
    try {
      final _notes = await _moveGitNotes(notes, destFolder);
      return Result(_notes);
    } on ServerException catch (error) {
      return Result.fail(error);
    }
  }

  Future<List<Note>> _moveGitNotes(
    List<Note> notes,
    NotesFolderFS destFolder,
  ) async {
    var newNotes = <Note>[];
    try {
      return await _gitOpLock.synchronized(() async {
        Log.d("Got moveNotes lock");

        var oldPaths = <String>[];
        var newPaths = <String>[];

        for (final note in notes) {
          var moveNoteResult = NotesFolderFS.moveNote(note, destFolder);
          // FIXME: We need to validate that this wont cause any problems!
          //        Transaction needs to be reverted
          if (moveNoteResult.isFailure) {
            Log.e("moveNotes", result: moveNoteResult);
            throw StorageException();
          }
          var newNote = moveNoteResult.getOrThrow();
          oldPaths.add(note.filePath);
          newPaths.add(newNote.filePath);

          newNotes.add(newNote);
        }

        final result = await gitRepo.moveNotes(oldPaths, newPaths);
        if (result.isFailure) {
          Log.e("moveNotes", result: result);
          throw ServerException();
        }

        return newNotes;
      });
    } on Exception catch (e) {
      Log.e('$e');
      throw ServerException();
    }
  }

//**************** Rename Notes ****************

  Future<Result<Note>> renameNote(
    Note fromNote,
    String newFileName,
  ) async {
    try {
      var toNote = fromNote.copyWithFileName(newFileName);
      toNote = toNote.updateModified();
      _renameStorageNotes(fromNote, toNote);

      await _renameGitNotes(fromNote.filePath, toNote.filePath);
      return Result(toNote);
    } on ServerException catch (error) {
      return Result.fail(error);
    }
  }

  Result _renameStorageNotes(Note fromNote, Note toNote) {
    if (io.File(toNote.fullFilePath).existsSync()) {
      return Result.fail(
        Exception('Destination Note exists'),
      );
    }
    final renameResult = fromNote.parent.renameNote(fromNote, toNote);
    if (renameResult.isFailure) {
      return fail(renameResult);
    }
    return renameResult;
  }

  Future<void> _renameGitNotes(
    String oldPaths,
    String newPaths,
  ) async {
    try {
      await _gitOpLock.synchronized(() async {
        final result = await gitRepo.renameNote(
          oldPaths,
          newPaths,
        );
        if (result.isFailure) {
          Log.e("renameNote failed", result: result);
          throw ServerException();
        }
      });
    } on Exception catch (e) {
      Log.e('$e');
      throw ServerException();
    }
  }
}

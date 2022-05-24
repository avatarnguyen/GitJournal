import 'package:dart_git/utils/result.dart';
import 'package:gitjournal/core/git_repo.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/note_storage.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:synchronized/synchronized.dart';

class StorageException implements Exception {}

class NoteUsecases {
  final GitNoteRepository gitRepo;

  NoteUsecases(this.gitRepo);

  final _gitOpLock = Lock();

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

    final _storageResult = await NoteStorage.save(note);
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
}

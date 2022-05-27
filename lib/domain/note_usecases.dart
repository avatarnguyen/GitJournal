import 'package:collection/collection.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/exceptions.dart';
import 'package:git_bindings/git_bindings.dart';
import 'package:gitjournal/core/commit_message_builder.dart';
import 'package:gitjournal/core/file/file_exceptions.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/git_repo.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/note_storage.dart';
import 'package:gitjournal/core/notes_cache.dart';
import 'package:gitjournal/domain/exception.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/settings/git_config.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';
import 'package:universal_io/io.dart' as io;

class NoteUsecases {
  final String repoPath;
  final GitConfig gitConfig;
  final NotesCache notesCache;
  final NotesFolderFS rootFolder;

  NoteUsecases({
    required this.notesCache,
    required this.rootFolder,
    required this.repoPath,
    required this.gitConfig,
    Lock? gitOpLock,
  }) {
    _gitOpLock = gitOpLock ?? Lock();
    _gitRepo = GitNoteRepository(gitRepoPath: repoPath, config: gitConfig);
  }

  late final Lock _gitOpLock;
  late final GitNoteRepository _gitRepo;

  final _loadLock = Lock();
  final _networkLock = Lock();

  Future<void> loadNotesFromCache() async {
    return await notesCache.load(rootFolder);
  }

  Future<void> cacheNotesFromRoot() async {
    return await notesCache.buildCache(rootFolder);
  }

  Future<void> clearNoteCache() async {
    await notesCache.clear();
  }

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

        var result = await _gitRepo.addNote(note);
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

        var result = await _gitRepo.updateNote(note);
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

        var result = await _gitRepo.removeNotes(notes);
        if (result.isFailure) {
          Log.e("remove Note failed", result: result);
          throw ServerException();
        }
      });
    } on Exception catch (e) {
      Log.e("remove Note exception $e");
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

        var result = await _gitRepo.resetLastCommit();
        if (result.isFailure) {
          Log.e("undoRemoveNote", result: result);
          throw ServerException();
        }
      });
    } on Exception catch (e) {
      Log.e("reset last commit exception $e");
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

        final result = await _gitRepo.moveNotes(oldPaths, newPaths);
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
      final result = _renameStorageNotes(fromNote, toNote);
      if (result.isFailure) {
        return fail(result);
      }
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
        final result = await _gitRepo.renameNote(
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

//**************** Load Notes ****************
  Future<Result<int?>> loadGitNotes(String repoPath) async {
    try {
      return _loadLock.synchronized(() async {
        var r = await rootFolder.loadRecursively();
        if (r.isFailure) {
          if (r.error is FileStorageCacheIncomplete) {
            var ex = r.error as FileStorageCacheIncomplete;
            Log.i("FileStorageCacheIncomplete ${ex.path}");
            var repo = await GitAsyncRepository.load(repoPath).getOrThrow();
            await commitUnTrackedChanges(repo, gitConfig).throwOnError();
            // await _resetFileStorage();
            return Result.fail(ex);
          }
        }
        // await _notesCache.buildCache(rootFolder);

        final changes = await _gitRepo.numChanges();
        return Result(changes);
      });
    } on Exception catch (error) {
      Log.e('$error');
      return Result.fail(error);
    }
  }

  static Future<Result<void>> commitUnTrackedChanges(
    GitAsyncRepository repo,
    GitConfig gitConfig,
  ) async {
    return await _commitUnTracked(repo, gitConfig);
  }

  static Future<Result<void>> _commitUnTracked(
      GitAsyncRepository repo, GitConfig gitConfig) async {
    var timer = Stopwatch()..start();
    //
    // Check for un-committed files and save them
    //
    var addR = await repo.add('.');
    if (addR.isFailure) {
      return fail(addR);
    }

    var commitR = await repo.commit(
      message: CommitMessageBuilder().autoCommit(),
      author: GitAuthor(
        name: gitConfig.gitAuthor,
        email: gitConfig.gitAuthorEmail,
      ),
    );
    if (commitR.isFailure) {
      if (commitR.error is! GitEmptyCommit) {
        Log.i('_commitUntracked NoCommit: ${timer.elapsed}');
        return fail(commitR);
      }
    }

    Log.i('_commitUntracked: ${timer.elapsed}');
    return Result(null);
  }

  /// Add a GitIgnore file if no file is present. This way we always at least have
  /// one commit. It makes doing a git pull and push easier
  Future<void> ensureOneCommitInRepo({
    required String repoPath,
  }) async {
    try {
      var dirList = await io.Directory(repoPath).list().toList();
      var anyFileInRepo = dirList.firstWhereOrNull(
        (fs) => fs.statSync().type == io.FileSystemEntityType.file,
      );
      if (anyFileInRepo == null) {
        Log.i("Adding .ignore file");
        var ignoreFile = io.File(path.join(repoPath, ".gitignore"));
        ignoreFile.createSync();

        var repo = GitRepo(folderPath: repoPath);
        await repo.add('.gitignore');

        await repo.commit(
          message: "Add gitignore file",
          authorEmail: gitConfig.gitAuthorEmail,
          authorName: gitConfig.gitAuthor,
        );
      }
    } catch (ex, st) {
      Log.e("_ensureOneCommitInRepo", ex: ex, stacktrace: st);
    }
  }

//**************** Git ****************
  Future<void> gitPush() async {
    await _networkLock.synchronized(() async {
      await _gitRepo.push().throwOnError();
    });
  }

  Future<void> gitMerge() async {
    await _gitOpLock.synchronized(() async {
      var r = await _gitRepo.merge();
      if (r.isFailure) {
        var ex = r.error!;
        // When there is nothing to merge into
        if (ex is! GitRefNotFound) {
          throw ex;
          // FIXME: Do not throw this exception, try to solve it somehow!!
        }
      }
    });
  }

  Future<void> gitFetch() async {
    await _networkLock.synchronized(() async {
      await _gitRepo.fetch().throwOnError();
    });
  }

  Future<Result> gitLoadAsync(String repoPath) async {
    final repoR = await GitAsyncRepository.load(repoPath);
    if (repoR.isFailure) {
      Log.e("SyncNotes Failed to Load Repo", result: repoR);
      return repoR;
    }
    final repo = repoR.getOrThrow();
    await _commitUnTracked(repo, gitConfig).throwOnError();
    return Result(repo);
  }
}

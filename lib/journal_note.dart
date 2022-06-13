import 'package:dart_git/dart_git.dart';
import 'package:gitjournal/analytics/analytics.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/git_repo.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/note_storage.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/repository_lock.dart';
import 'package:path/path.dart' as path;
import 'package:time/time.dart';
import 'package:universal_io/io.dart' as io;

class JournalNote {
  final GitJournalRepo gitJournal;
  final GitNoteRepository gitNoteRepo;

  JournalNote(this.gitJournal, this.gitNoteRepo);

  Future<Result<Note>> rename(Note originalNote, String newFileName) async {
    assert(!newFileName.contains(path.separator));
    assert(originalNote.oid.isNotEmpty);

    var toNote = originalNote.copyWithFileName(newFileName);
    if (io.File(toNote.fullFilePath).existsSync()) {
      var ex = Exception('Destination Note exists');
      return Result.fail(ex);
    }

    Result<void> renameR = renameLocalNote(originalNote, toNote);
    if (renameR.isFailure) {
      return fail(renameR);
    }

    final gitOpLock = RepositoryLock().gitOpLock;
    var _ = await gitOpLock.synchronized(() async {
      Result<void> result = await renameGitNote(originalNote, toNote);
      if (result.isFailure) {
        Log.e("renameNote", result: result);
        return fail(result);
      }

      increaseNumChanges();
    });

    syncNotes();
    return Result(toNote);
  }

  void syncNotes() {
    gitJournal.syncNotesWithoutWaiting();
  }

  void increaseNumChanges() {
    gitJournal.increaseNumChanges();
  }

  void decreaseNumChanges() {
    gitJournal.decreaseNumChanges();
  }

  Result<void> renameLocalNote(Note fromNote, Note toNote) {
    var renameR = fromNote.parent.renameNote(fromNote, toNote);
    return renameR;
  }

  Future<Result<void>> renameGitNote(Note fromNote, Note toNote) async {
    Log.i('------------- [JournalNote] Git Note Repo: ${gitNoteRepo.hashCode}'
        ' ---------------');

    var result = await gitNoteRepo.renameNote(
      fromNote.filePath,
      toNote.filePath,
    );
    return result;
  }

  Future<Result<Note>> update(Note oldNote, Note newNote) async {
    assert(oldNote.oid.isNotEmpty);
    assert(newNote.oid.isEmpty);

    logEvent(Event.NoteUpdated);

    assert(oldNote.filePath == newNote.filePath);
    assert(oldNote.parent == newNote.parent);

    var modifiedNote = newNote.updateModified();

    var result = await NoteStorage.save(modifiedNote);
    if (result.isFailure) {
      Log.e("Note saving failed",
          ex: result.error, stacktrace: result.stackTrace);
      return fail(result);
    }
    modifiedNote = result.getOrThrow();

    newNote.parent.updateNote(modifiedNote);

    final gitOpLock = RepositoryLock().gitOpLock;
    await gitOpLock.synchronized(() async {
      Log.d("Got updateNote lock");

      var result = await gitNoteRepo.updateNote(modifiedNote);
      if (result.isFailure) {
        Log.e("updateNote", result: result);
        return;
      }

      increaseNumChanges();
      // notifyListeners();
    });

    syncNotes();
    return Result(modifiedNote);
  }

  Future<Result<Note>> addNote(Note note) async {
    assert(note.oid.isEmpty);
    logEvent(Event.NoteAdded);

    note = note.updateModified();

    var storageResult = await NoteStorage.save(note);
    if (storageResult.isFailure) {
      Log.e("Note saving failed",
          ex: storageResult.error, stacktrace: storageResult.stackTrace);
      return fail(storageResult);
    }
    note = storageResult.getOrThrow();

    note.parent.add(note);

    final gitOpLock = RepositoryLock().gitOpLock;
    await gitOpLock.synchronized(() async {
      Log.d("Got addNote lock");

      var result = await gitNoteRepo.addNote(note);
      if (result.isFailure) {
        Log.e("addNote", result: result);
        return;
      }

      increaseNumChanges();
    });

    syncNotes();
    return Result(note);
  }

  void remove(Note note) => removeNotes([note]);

  Future<void> removeNotes(List<Note> notes) async {
    logEvent(Event.NoteDeleted);

    final gitOpLock = RepositoryLock().gitOpLock;
    await gitOpLock.synchronized(() async {
      Log.d("Got removeNote lock");

      // FIXME: What if the Note hasn't yet been saved?
      for (var note in notes) {
        note.parent.remove(note);
      }
      var result = await gitNoteRepo.removeNotes(notes);
      if (result.isFailure) {
        Log.e("removeNotes", result: result);
        return;
      }

      increaseNumChanges();

      // FIXME: Is there a way of figuring this amount dynamically?
      // The '4 seconds' is taken from snack_bar.dart -> _kSnackBarDisplayDuration
      // We wait an aritfical amount of time, so that the user has a chance to undo
      // their delete operation, and that commit is not synced with the server, till then.
      await Future.delayed(4.seconds);
    });

    syncNotes();
  }

  Future<void> undoRemoveNote(Note note) async {
    logEvent(Event.NoteUndoDeleted);

    final gitOpLock = RepositoryLock().gitOpLock;
    await gitOpLock.synchronized(() async {
      Log.d("Got undoRemoveNote lock");

      note.parent.add(note);
      var result = await gitNoteRepo.resetLastCommit();
      if (result.isFailure) {
        Log.e("undoRemoveNote", result: result);
        return;
      }

      decreaseNumChanges();
    });

    syncNotes();
  }

  Future<Result<Note>> move(Note note, NotesFolderFS destFolder) async {
    var result = await moveNotes([note], destFolder);
    if (result.isFailure) return fail(result);

    var newNotes = result.getOrThrow();
    assert(newNotes.length == 1);
    return Result(newNotes.first);
  }

  Future<Result<List<Note>>> moveNotes(
      List<Note> notes, NotesFolderFS destFolder) async {
    notes = notes
        .where((n) => n.parent.folderPath != destFolder.folderPath)
        .toList();

    if (notes.isEmpty) {
      var ex = Exception(
        "All selected notes are already in `${destFolder.folderPath}`",
      );
      return Result.fail(ex);
    }

    var newNotes = <Note>[];

    logEvent(Event.NoteMoved);

    final gitOpLock = RepositoryLock().gitOpLock;
    var r = await gitOpLock.synchronized(() async {
      Log.d("Got moveNote lock");

      var oldPaths = <String>[];
      var newPaths = <String>[];
      for (var note in notes) {
        var result = NotesFolderFS.moveNote(note, destFolder);
        // FIXME: We need to validate that this wont cause any problems!
        //        Transaction needs to be reverted
        if (result.isFailure) {
          Log.e("moveNotes", result: result);
          return fail(result);
        }
        var newNote = result.getOrThrow();
        oldPaths.add(note.filePath);
        newPaths.add(newNote.filePath);

        newNotes.add(newNote);
      }

      var result = await gitNoteRepo.moveNotes(oldPaths, newPaths);
      if (result.isFailure) {
        Log.e("moveNotes", result: result);
        return fail(result);
      }

      increaseNumChanges();
      // notifyListeners();
      return Result(null);
    });
    if (r.isFailure) return fail(r);

    syncNotes();
    return Result(newNotes);
  }
}

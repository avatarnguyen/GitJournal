import 'package:dart_git/dart_git.dart';
import 'package:gitjournal/core/git_repo.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/repository_lock.dart';
import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart' as io;

class JournalNote {
  final GitJournalRepo gitJournal;
  final GitNoteRepository gitNoteRepo;

  JournalNote(this.gitJournal, this.gitNoteRepo);

  Future<Result<Note>> rename(Note originalNote, String newFileName) async {
    assert(!newFileName.contains(path.separator));
    assert(originalNote.oid.isNotEmpty);

    // var gitJournal = context.read<GitJournalRepo>();
    var toNote = originalNote.copyWithFileName(newFileName);
    if (io.File(toNote.fullFilePath).existsSync()) {
      var ex = Exception('Destination Note exists');
      return Result.fail(ex);
    }
    // var renameResult = await container.renameNote(originalNote, newFileName);

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

      gitJournal.increaseNumChanges();
    });

    gitJournal.syncNotesWithoutWaiting();
    return Result(toNote);
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
}

import 'package:dart_git/dart_git.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/repository_lock.dart';
import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart' as io;

class JournalNote {
  final GitJournalRepo gitJournal;

  JournalNote(this.gitJournal);

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

    Result<void> renameR = gitJournal.renameLocalNote(originalNote, toNote);
    if (renameR.isFailure) {
      return fail(renameR);
    }

    final gitOpLock = RepositoryLock().gitOpLock;
    var _ = await gitOpLock.synchronized(() async {
      Result<void> result =
          await gitJournal.renameGitNote(originalNote, toNote);
      if (result.isFailure) {
        Log.e("renameNote", result: result);
        return fail(result);
      }

      gitJournal.increaseNumChanges();
    });

    gitJournal.syncNotesWithoutWaiting();
    return Result(toNote);
  }
}

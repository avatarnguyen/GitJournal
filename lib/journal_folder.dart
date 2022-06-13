import 'package:dart_git/utils/result.dart';
import 'package:gitjournal/analytics/analytics.dart';
import 'package:gitjournal/core/folder/notes_folder_config.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/git_repo.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/repository_lock.dart';
import 'package:path/path.dart' as path;

class JournalFolder {
  final GitJournalRepo gitJournal;
  final GitNoteRepository gitNoteRepo;
  final NotesFolderConfig folderConfig;

  JournalFolder(this.gitJournal, this.gitNoteRepo, this.folderConfig);

  Future<Result<void>> create(NotesFolderFS parent, String folderName) async {
    logEvent(Event.FolderAdded);

    final gitOpLock = RepositoryLock().gitOpLock;
    var r = await gitOpLock.synchronized(() async {
      var newFolderPath = path.join(parent.folderPath, folderName);
      var newFolder = NotesFolderFS(parent, newFolderPath, folderConfig);
      var r = newFolder.create();
      if (r.isFailure) {
        Log.e("createFolder", result: r);
        return fail(r);
      }

      Log.d("Created New Folder: " + newFolderPath);
      parent.addFolder(newFolder);

      var result = await gitNoteRepo.addFolder(newFolder);
      if (result.isFailure) {
        Log.e("createFolder", result: result);
        return fail(result);
      }

      increaseNumChanges();
      // notifyListeners();
      return Result(null);
    });
    if (r.isFailure) return fail(r);

    syncNotes();
    return Result(null);
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
}

import 'package:dart_git/dart_git.dart';
import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/git_repo.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';

class FolderUsecases {
  final GitNoteRepository gitRepo;

  FolderUsecases(
    this.gitRepo, {
    Lock? gitOpLock,
  }) {
    _gitOpLock = gitOpLock ?? Lock();
  }

  late final Lock _gitOpLock;

  Future<Result<void>> createFolder(
    NotesFolderFS parent,
    String folderName,
    NotesFolderConfig folderConfig,
  ) async {
    return await _gitOpLock.synchronized(() async {
      var newFolderPath = path.join(parent.folderPath, folderName);
      var newFolder = NotesFolderFS(parent, newFolderPath, folderConfig);
      var r = newFolder.create();
      if (r.isFailure) {
        Log.e("createFolder", result: r);
        return fail(r);
      }

      Log.d("Created New Folder: " + newFolderPath);
      parent.addFolder(newFolder);

      var result = await gitRepo.addFolder(newFolder);
      if (result.isFailure) {
        Log.e("createFolder", result: result);
        return fail(result);
      }

      return Result(null);
    });
  }
}

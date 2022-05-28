import 'package:dart_git/dart_git.dart';
import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/git_repo.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/settings/git_config.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';
import 'package:universal_io/io.dart' as io;

class FolderUsecases {
  final String repoPath;
  final GitConfig gitConfig;
  final NotesFolderConfig folderConfig;

  FolderUsecases({
    required this.repoPath,
    required this.gitConfig,
    required this.folderConfig,
    Lock? gitOpLock,
  }) {
    _gitOpLock = gitOpLock ?? Lock();
    _gitRepo = GitNoteRepository(gitRepoPath: repoPath, config: gitConfig);
  }

  late final Lock _gitOpLock;
  late final GitNoteRepository _gitRepo;

  Future<void> saveFolderConfig() async {
    await folderConfig.save();
  }

  Future<void> saveGitConfig() async {
    await gitConfig.save();
  }

  //**************** Create Folder ****************
  Future<Result<void>> createFolder(
    NotesFolderFS parent,
    String folderName,
  ) async {
    return await _gitOpLock.synchronized(() async {
      final _storageResult = _createStorageFolder(parent, folderName);
      if (_storageResult.isFailure) {
        return _storageResult;
      }

      final gitResult = await _gitRepo.addFolder(_storageResult.getOrThrow());
      if (gitResult.isFailure) {
        Log.e("createFolder", result: gitResult);
        return fail(gitResult);
      }

      return Result(null);
    });
  }

  Result<NotesFolderFS> _createStorageFolder(
    NotesFolderFS parent,
    String folderName,
  ) {
    var newFolderPath = path.join(parent.folderPath, folderName);
    var newFolder = NotesFolderFS(parent, newFolderPath, folderConfig);
    var r = newFolder.create();
    if (r.isFailure) {
      Log.e("createFolder", result: r);
      return fail(r);
    }

    Log.d("Created New Folder: " + newFolderPath);
    parent.addFolder(newFolder);
    return Result(newFolder);
  }

//**************** Rename Folder ****************
  Future<Result> renameFolder(NotesFolderFS folder, String newName) async {
    return await _gitOpLock.synchronized(() async {
      final oldFolderPath = folder.folderPath;
      Log.d("Renaming Folder from $oldFolderPath -> $newName");
      folder.rename(newName);

      return await _gitRenameFolder(oldFolderPath, folder);
    });
  }

  Future<Result<void>> _gitRenameFolder(
      String oldFolderPath, NotesFolderFS folder) async {
    return await _gitRepo.renameFolder(
      oldFolderPath,
      folder.folderPath,
    );
  }

//**************** Remove Folder ****************
  Future<Result> removeFolder(NotesFolderFS folder) async {
    return await _gitOpLock.synchronized(() async {
      Log.d("Got removeFolder lock");
      Log.d("Removing Folder: " + folder.folderPath);

      folder.parentFS!.removeFolder(folder);
      Result<void> result = await _gitRemoveFolder(folder);
      return result;
    });
  }

  Future<Result<void>> _gitRemoveFolder(NotesFolderFS folder) async {
    final result = await _gitRepo.removeFolder(folder);
    return result;
  }

  Result<bool> fileExists(String path) {
    return catchAllSync(() {
      var type = io.FileSystemEntity.typeSync(path);
      return Result(type != io.FileSystemEntityType.notFound);
    });
  }
}

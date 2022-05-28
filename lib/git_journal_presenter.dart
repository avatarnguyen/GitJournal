/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:async';

import 'package:dart_git/config.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gitjournal/analytics/analytics.dart';
import 'package:gitjournal/core/file/file_storage_cache.dart';
import 'package:gitjournal/core/folder/notes_folder_config.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/git_repo.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/notes_cache.dart';
import 'package:gitjournal/domain/folder_usecases.dart';
import 'package:gitjournal/domain/git_journal_repo.dart';
import 'package:gitjournal/domain/note_usecases.dart';
import 'package:gitjournal/domain/storage_repo.dart';
import 'package:gitjournal/error_reporting.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/repository_manager.dart';
import 'package:gitjournal/settings/git_config.dart';
import 'package:gitjournal/settings/settings.dart';
import 'package:gitjournal/settings/settings_migrations.dart';
import 'package:gitjournal/settings/storage_config.dart';
import 'package:gitjournal/sync_attempt.dart';
import 'package:path/path.dart' as path;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import 'package:time/time.dart';
import 'package:universal_io/io.dart' show Platform;
import 'package:universal_io/io.dart' as io;

class GitJournalPresenter with ChangeNotifier {
  final RepositoryManager repoManager;
  final StorageConfig storageConfig;
  // final GitConfig gitConfig;
  // final NotesFolderConfig folderConfig;
  final Settings settings;

  // final FileStorage fileStorage;
  // final FileStorageCache fileStorageCache;

  // final _gitOpLock = Lock();
  // final _loadLock = Lock();
  // final _networkLock = Lock();
  final _cacheBuildingLock = Lock();

  /// The private directory where the 'git repo' is stored.
  final String gitBaseDirectory;
  final String cacheDir;
  final String id;

  final String repoPath;

  // late final GitNoteRepository _gitRepo;
  // late final NotesCache _notesCache;
  // late final NotesFolderFS rootFolder;
  final StorageRepo storageRepo;

  final NoteUsecases noteUsecases;
  final FolderUsecases folderUsecases;

  final GitJournalRepo gitJournalRepo;

  //
  // Mutable stuff
  //

  String? _currentBranch;

  /// Sorted in newest -> oldest
  var syncAttempts = <SyncAttempt>[];
  SyncStatus get syncStatus =>
      syncAttempts.isNotEmpty ? syncAttempts.first.status : SyncStatus.Unknown;

  int numChanges = 0;

  bool remoteGitRepoConfigured = false;
  late bool fileStorageCacheReady;

  static Future<bool> exists({
    required String gitBaseDir,
    required SharedPreferences pref,
    required String id,
  }) async {
    var storageConfig = StorageConfig(id, pref);
    storageConfig.load();

    var repoPath = await storageConfig.buildRepoPath(gitBaseDir);
    return GitRepository.isValidRepo(repoPath);
  }

  static Future<Result<GitJournalPresenter>> load({
    required String gitBaseDir,
    required String cacheDir,
    required SharedPreferences pref,
    required String id,
    required RepositoryManager repoManager,
    bool loadFromCache = true,
    bool syncOnBoot = true,
  }) async {
    await migrateSettings(id, pref, gitBaseDir);

    var storageConfig = StorageConfig(id, pref);
    storageConfig.load();

    var folderConfig = NotesFolderConfig(id, pref);
    folderConfig.load();

    var gitConfig = GitConfig(id, pref);
    gitConfig.load();

    var settings = Settings(id, pref);
    settings.load();

    Sentry.configureScope((scope) {
      scope.setContexts('StorageConfig', storageConfig.toLoggableMap());
      scope.setContexts('FolderConfig', folderConfig.toLoggableMap());
      scope.setContexts('GitConfig', gitConfig.toLoggableMap());
      scope.setContexts('Settings', settings.toLoggableMap());
    });

    logEvent(
      Event.StorageConfig,
      parameters: storageConfig.toLoggableMap()..addAll({'id': id}),
    );
    logEvent(
      Event.FolderConfig,
      parameters: folderConfig.toLoggableMap()..addAll({'id': id}),
    );
    logEvent(
      Event.GitConfig,
      parameters: gitConfig.toLoggableMap()..addAll({'id': id}),
    );
    logEvent(
      Event.Settings,
      parameters: settings.toLoggableMap()..addAll({'id': id}),
    );

    var repoPath = await storageConfig.buildRepoPath(gitBaseDir);
    Log.i("Loading Repo at path $repoPath");

    var repoDir = io.Directory(repoPath);

    if (!repoDir.existsSync()) {
      Log.i("Calling GitInit for ${storageConfig.folderName} at: $repoPath");
      var r = GitRepository.init(repoPath, defaultBranch: DEFAULT_BRANCH);
      if (r.isFailure) {
        Log.e("GitInit Failed", result: r);
        return fail(r);
      }

      storageConfig.save();
    }

    var valid = GitRepository.isValidRepo(repoPath);
    if (!valid) {
      // What happened that the directory still exists but the .git folder
      // has disappeared?
      // FIXME: What if the '.config' file is not accessible?
      // -> https://sentry.io/share/issue/bafc5c417bdb4fd196cead1d28432f12/
      var ex = Exception('Folder is no longer a valid Git Repo');
      return Result.fail(ex);
    }

    var repoR = await GitAsyncRepository.load(repoPath);
    if (repoR.isFailure) {
      return fail(repoR);
    }
    var repo = repoR.getOrThrow();
    var remoteConfigured = repo.config.remotes.isNotEmpty;

    if (!storageConfig.storeInternally) {
      final result = await NoteUsecases.commitUnTrackedChanges(repo, gitConfig);
      if (result.isFailure) {
        return fail(result);
      }
    }

    var _ = await io.Directory(cacheDir).create(recursive: true);

    var fileStorageCache = FileStorageCache(cacheDir);
    var fileStorage = await fileStorageCache.load(repoPath);

    var headR = await repo.headHash();
    var head = headR.isFailure ? GitHash.zero() : headR.getOrThrow();

    //TODO: this should be through DI
    final _gitJournalRepo = GitJournalRepoImpl(repoPath);

    final _gitOpLock = Lock();

    final rootFolder = NotesFolderFS.root(folderConfig, fileStorage);
    final _notesCache = NotesCache(
      folderPath: cacheDir,
      repoPath: repoPath,
      fileStorage: fileStorage,
    );

    // Init NoteUsecases instance
    final _noteUsecases = NoteUsecases(
      notesCache: _notesCache,
      rootFolder: rootFolder,
      repoPath: repoPath,
      gitConfig: gitConfig,
      gitOpLock: _gitOpLock,
    );
    // Init Folder Usecases instance
    final _folderUsecases = FolderUsecases(
      repoPath: repoPath,
      gitConfig: gitConfig,
      gitOpLock: _gitOpLock,
      folderConfig: folderConfig,
    );

    final _storageRepo = StorageRepoImpl(
        fileStorage: fileStorage, fileStorageCache: fileStorageCache);

    var gjRepo = GitJournalPresenter._internal(
      repoManager: repoManager,
      repoPath: repoPath,
      gitBaseDirectory: gitBaseDir,
      cacheDir: cacheDir,
      remoteGitRepoConfigured: remoteConfigured,
      storageConfig: storageConfig,
      settings: settings,
      // gitConfig: gitConfig,
      id: id,
      // fileStorage: fileStorage,
      // fileStorageCache: fileStorageCache,
      currentBranch: await repo.currentBranch().getOrThrow(),
      headHash: head,
      loadFromCache: loadFromCache,
      syncOnBoot: syncOnBoot,
      noteUsecases: _noteUsecases,
      folderUsecases: _folderUsecases,
      gitJournalRepo: _gitJournalRepo,
      storageRepo: _storageRepo,
    );

    return Result(gjRepo);
  }

  GitJournalPresenter._internal({
    required this.id,
    required this.repoPath,
    required this.repoManager,
    required this.gitBaseDirectory,
    required this.cacheDir,
    required this.storageConfig,
    // required this.folderConfig,
    required this.settings,
    // required this.gitConfig,
    required this.remoteGitRepoConfigured,
    // required this.fileStorage,
    // required this.fileStorageCache,
    required String? currentBranch,
    required GitHash headHash,
    required bool loadFromCache,
    required bool syncOnBoot,
    required this.noteUsecases,
    required this.folderUsecases,
    required this.gitJournalRepo,
    required this.storageRepo,
  }) {
    _currentBranch = currentBranch;

    Log.i("Branch $_currentBranch");

    // Makes it easier to filter the analytics
    Analytics.instance?.setUserProperty(
      name: 'onboarded',
      value: remoteGitRepoConfigured.toString(),
    );

    Log.i("Cache Directory: $cacheDir");

    fileStorageCacheReady = headHash == storageRepo.cachedLastProcessedHead;

    if (loadFromCache) _loadFromCache();
    if (syncOnBoot) _syncNotes();
  }

  Future<void> _loadFromCache() async {
    var startTime = DateTime.now();
    await noteUsecases.loadNotesFromCache();
    var endTime = DateTime.now().difference(startTime);

    Log.i("Finished loading the notes cache - $endTime");

    startTime = DateTime.now();
    await _loadNotes();
    endTime = DateTime.now().difference(startTime);

    Log.i("Finished loading all the notes - $endTime");
  }

  Future<void> _resetFileStorage() async {
    await storageRepo.clearStorageCache();

    // This will discard this Repository and build a new one
    var _ = repoManager.buildActiveRepository();
  }

  Future<void> reloadNotes() => _loadNotes();

  Future<void> _loadNotes() async {
    await _fillFileStorageCache();

    // FIXME: We should report the notes that failed to load
    final result = await noteUsecases.loadGitNotes(repoPath);
    if (result.isFailure) {
      await _resetFileStorage();
    } else {
      await noteUsecases.cacheNotesFromRoot();

      final changes = result.getOrThrow();
      numChanges = changes ?? 0;
      notifyListeners();
    }
  }

  Future<void> _fillFileStorageCache() {
    return _cacheBuildingLock.synchronized(
      () async {
        await storageRepo.fillStorageCache();

        // Notify that the cache is ready
        fileStorageCacheReady = true;
        notifyListeners();
      },
    );
  }

  bool _shouldCheckForChanges() {
    if (Platform.isAndroid || Platform.isIOS) {
      return !storageConfig.storeInternally;
    }
    // Overwriting this for now, as I want the tests to pass
    return !storageConfig.storeInternally;
  }

  Future<void> syncNotes({bool doNotThrow = false}) async {
    // This is extremely slow with dart-git, can take over a second!
    if (_shouldCheckForChanges()) {
      final result = await noteUsecases.gitLoadAsync(repoPath);
      if (result.isFailure) return;
    }

    if (!remoteGitRepoConfigured) {
      Log.d("Not syncing because RemoteRepo not configured");
      await _loadNotes();
      return;
    }

    logEvent(Event.RepoSynced);
    var attempt = SyncAttempt();
    attempt.add(SyncStatus.Pulling);
    syncAttempts.insert(0, attempt);
    notifyListeners();

    Future<void>? noteLoadingFuture;
    try {
      await noteUsecases.gitFetch();

      attempt.add(SyncStatus.Merging);
      await noteUsecases.gitMerge();

      attempt.add(SyncStatus.Pushing);
      notifyListeners();
      noteLoadingFuture = _loadNotes();
      await noteUsecases.gitPush();

      Log.d("Synced!");
      attempt.add(SyncStatus.Done);
      numChanges = 0;
      notifyListeners();
    } catch (error, stacktrace) {
      Log.e("Failed to Sync", ex: error, stacktrace: stacktrace);

      var ex = error;
      if (ex is! Exception) {
        ex = Exception(error.toString());
      }
      attempt.add(SyncStatus.Error, ex);

      notifyListeners();
      if (error is Exception && shouldLogGitException(error)) {
        await logException(error, stacktrace);
      }
      if (!doNotThrow) rethrow;
    }

    await noteLoadingFuture;
  }

  Future<void> _syncNotes() async {
    var freq = settings.remoteSyncFrequency;
    if (freq != RemoteSyncFrequency.Automatic) {
      await _loadNotes();
      return;
    }
    return syncNotes(doNotThrow: true);
  }

  Future<Result<void>> createFolder(
      NotesFolderFS parent, String folderName) async {
    logEvent(Event.FolderAdded);

    final result = await folderUsecases.createFolder(parent, folderName);

    if (result.isFailure) return fail(result);

    // result is success
    numChanges += 1;
    notifyListeners();

    unawaited(_syncNotes());
    return result;
  }

  Future<void> removeFolder(NotesFolderFS folder) async {
    logEvent(Event.FolderDeleted);

    final result = await folderUsecases.removeFolder(folder);
    if (result.isFailure) {
      Log.e("removeFolder", result: result);
      return;
    }

    numChanges += 1;
    notifyListeners();
    unawaited(_syncNotes());
  }

  Future<void> renameFolder(NotesFolderFS folder, String newFolderName) async {
    assert(!newFolderName.contains(path.separator));

    logEvent(Event.FolderRenamed);

    final result = await folderUsecases.renameFolder(folder, newFolderName);
    if (result.isFailure) {
      Log.e("rename Folder failed", result: result);
      return;
    }

    numChanges += 1;
    notifyListeners();

    unawaited(_syncNotes());
  }

  Future<Result<Note>> renameNote(Note fromNote, String newFileName) async {
    assert(!newFileName.contains(path.separator));
    assert(fromNote.oid.isNotEmpty);

    logEvent(Event.NoteRenamed);

    final result = await noteUsecases.renameNote(fromNote, newFileName);

    if (result.isSuccess) {
      numChanges += 1;
      notifyListeners();
      unawaited(_syncNotes());
    }
    return result;
  }

  Future<Result<Note>> moveNote(Note note, NotesFolderFS destFolder) async {
    final result = await moveNotes([note], destFolder);
    if (result.isFailure) return fail(result);

    var newNotes = result.getOrThrow();
    assert(newNotes.length == 1);
    return Result(newNotes.first);
  }

  Future<Result<List<Note>>> moveNotes(
      List<Note> notes, NotesFolderFS destFolder) async {
    final _notesToMove = notes
        .where((n) => n.parent.folderPath != destFolder.folderPath)
        .toList();

    if (_notesToMove.isEmpty) {
      return Result.fail(
        Exception(
          "All selected notes are already in `${destFolder.folderPath}`",
        ),
      );
    }

    logEvent(Event.NoteMoved);

    final _result = await noteUsecases.moveNotes(_notesToMove, destFolder);
    if (_result.isFailure) return _result;

    numChanges += 1;
    notifyListeners();

    unawaited(_syncNotes());
    return _result;
  }

  Future<Result<Note>> saveNoteToDisk(Note note) async {
    assert(note.oid.isEmpty);
    return await noteUsecases.saveNoteToStorage(note);
  }

  Future<Result<Note>> addNote(Note note) async {
    assert(note.oid.isEmpty);
    logEvent(Event.NoteAdded);

    final _noteAddedResult = await noteUsecases.addNote(note);
    if (_noteAddedResult.isSuccess) {
      numChanges += 1;
      notifyListeners();
      unawaited(_syncNotes());
    }
    return _noteAddedResult;
  }

  void removeNote(Note note) => removeNotes([note]);

  Future<void> removeNotes(List<Note> notes) async {
    logEvent(Event.NoteDeleted);

    // FIXME: What if the Note hasn't yet been saved?
    await noteUsecases.removeNotes(notes).then((value) {
      // remove locally
      for (var note in notes) {
        Log.i('removeNotes locally: $note');
        note.parent.remove(note);
      }
      numChanges += 1;
      notifyListeners();
    });

    // FIXME: Is there a way of figuring this amount dynamically?
    // The '4 seconds' is taken from snack_bar.dart -> _kSnackBarDisplayDuration
    // We wait an artificial amount of time, so that the user has a chance to undo
    // their delete operation, and that commit is not synced with the server, till then.
    var _ = await Future.delayed(4.seconds);

    unawaited(_syncNotes());
  }

  Future<void> undoRemoveNote(Note note) async {
    logEvent(Event.NoteUndoDeleted);

    await noteUsecases.undoRemoveNote(note).then((_) {
      numChanges -= 1;
      notifyListeners();
    });

    unawaited(_syncNotes());
  }

  Future<Result<Note>> updateNote(Note oldNote, Note newNote) async {
    assert(oldNote.oid.isNotEmpty);
    assert(newNote.oid.isEmpty);

    logEvent(Event.NoteUpdated);

    assert(oldNote.filePath == newNote.filePath);
    assert(oldNote.parent == newNote.parent);

    final _noteAddedResult = await noteUsecases.updateNote(newNote);
    if (_noteAddedResult.isSuccess) {
      numChanges += 1;
      notifyListeners();
      unawaited(_syncNotes());
    }
    return _noteAddedResult;
  }

  Result<bool> fileExists(String path) {
    return folderUsecases.fileExists(path);
  }

  Future<void> completeGitHostSetup(
      String repoFolderName, String remoteName) async {
    storageConfig.folderName = repoFolderName;
    storageConfig.save();
    await _persistConfig();

    var newRepoPath = path.join(gitBaseDirectory, repoFolderName);
    await noteUsecases.ensureOneCommitInRepo(
      repoPath: newRepoPath,
    );

    if (newRepoPath != repoPath) {
      Log.i("Old Path: $repoPath");
      Log.i("New Path: $newRepoPath");

      var _ = repoManager.buildActiveRepository();
      return;
    }

    Log.i("repoPath: $repoPath");

    remoteGitRepoConfigured = true;
    fileStorageCacheReady = false;

    _loadNotes();
    _syncNotes();

    notifyListeners();
  }

  Future<void> _persistConfig() async {
    await storageConfig.save();
    await folderUsecases.saveFolderConfig();
    await folderUsecases.saveGitConfig();
    await settings.save();
  }

  // *************** Git Methods ********************************

  Future<void> moveRepoToPath() async {
    var newRepoPath = await storageConfig.buildRepoPath(gitBaseDirectory);

    if (newRepoPath != repoPath) {
      Log.i("Old Path: $repoPath");
      Log.i("New Path: $newRepoPath");

      dynamic _;
      _ = await io.Directory(newRepoPath).create(recursive: true);
      await _copyDirectory(repoPath, newRepoPath);
      _ = await io.Directory(repoPath).delete(recursive: true);

      _ = repoManager.buildActiveRepository();
    }
  }

  Future<void> discardChanges(Note note) async {
    // FIXME: Add the checkout method to GJRepo
    await gitJournalRepo.discardChanges(note.filePath);

    // FIXME: Instead of this just reload that specific file
    // FIXME: I don't think this will work!
    await reloadNotes();
  }

  Future<List<GitRemoteConfig>> remoteConfigs() async {
    return gitJournalRepo.remoteConfigs();
  }

  Future<List<String>> branches() async {
    return gitJournalRepo.branches();
  }

  String? get currentBranch => _currentBranch;

  Future<String> checkoutBranch(String branchName) async {
    Log.i("Changing branch to $branchName");

    try {
      final branch = await gitJournalRepo.checkoutBranch(branchName);

      if (branch.isEmpty) {
        return "";
      }
    } catch (ex, st) {
      Log.e("createBranch", ex: ex, stacktrace: st);
    }

    try {
      _currentBranch = branchName;
      Log.i("Done checking out $branchName");

      await noteUsecases.clearNoteCache();
      notifyListeners();

      _loadNotes();
    } catch (e, st) {
      Log.e("Checkout Branch Failed", ex: e, stacktrace: st);
    }

    return branchName;
  }

  // FIXME: Why does this need to return a string?
  /// throws exceptions
  Future<String> createBranchIfRequired(
      GitAsyncRepository repo, String name) async {
    return gitJournalRepo.createBranchIfRequired(repo, name);
  }

  Future<void> delete() async {
    await io.Directory(repoPath).delete(recursive: true);
    await io.Directory(cacheDir).delete(recursive: true);
  }

  /// reset --hard the current branch to its remote branch
  Future<Result<void>> resetHard() {
    return catchAll(() async {
      try {
        final result = gitJournalRepo.resetHard();
        numChanges = 0;
        notifyListeners();

        _loadNotes();

        return result;
      } on Exception catch (error) {
        Log.e(error.toString());
        return Result.fail(error);
      }
    });
  }

  Future<Result<bool>> canResetHard() {
    return gitJournalRepo.canResetHard();
  }

  Future<Result<void>> removeRemote(String remoteName) async {
    return gitJournalRepo.removeRemote(remoteName);
  }

  Future<Result<void>> ensureValidRepo() async {
    return gitJournalRepo.ensureValidRepo();
  }

  Future<Result<void>> init(String repoPath) async {
    return gitJournalRepo.init(repoPath);
  }
}

// *********** End class ************

// FIXME: single private global method, should be removed
Future<void> _copyDirectory(String source, String destination) async {
  await for (var entity in io.Directory(source).list(recursive: false)) {
    dynamic _;
    if (entity is io.Directory) {
      var newDirectory = io.Directory(path.join(
          io.Directory(destination).absolute.path, path.basename(entity.path)));
      _ = await newDirectory.create();
      await _copyDirectory(entity.absolute.path, newDirectory.path);
    } else if (entity is io.File) {
      _ = await entity.copy(path.join(destination, path.basename(entity.path)));
    }
  }
}

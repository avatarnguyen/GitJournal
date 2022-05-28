import 'package:dart_git/plumbing/git_hash.dart';
import 'package:gitjournal/core/file/file_storage.dart';
import 'package:gitjournal/core/file/file_storage_cache.dart';
import 'package:gitjournal/error_reporting.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/settings/storage_config.dart';

abstract class StorageRepo {
  Future<void> clearStorageCache();
  Future<void> fillStorageCache();
  Future<void> saveConfig();
  Future<String> buildRepoPath(String directory);
  void changeFolderName(String name);
  bool get isStoreInternally;
  GitHash get cachedLastProcessedHead;
}

class StorageRepoImpl implements StorageRepo {
  final FileStorage fileStorage;
  final FileStorageCache fileStorageCache;
  final StorageConfig storageConfig;

  StorageRepoImpl({
    required this.fileStorage,
    required this.fileStorageCache,
    required this.storageConfig,
  });

  @override
  Future<void> clearStorageCache() async {
    await fileStorageCache.clear();
  }

  @override
  Future<void> fillStorageCache() async {
    var firstTime = fileStorage.head.isEmpty;

    var startTime = DateTime.now();
    await fileStorage.fill();
    var endTime = DateTime.now().difference(startTime);

    if (firstTime) Log.i("Built Git Time Cache - $endTime");

    var r = await fileStorageCache.save(fileStorage);
    if (r.isFailure) {
      Log.e("Failed to save FileStorageCache", result: r);
      logException(r.exception!, r.stackTrace!);
    }

    assert(cachedLastProcessedHead == fileStorage.head);
  }

  @override
  GitHash get cachedLastProcessedHead => fileStorageCache.lastProcessedHead;

  @override
  bool get isStoreInternally => storageConfig.storeInternally;

  @override
  void changeFolderName(String name) {
    storageConfig.folderName = name;
  }

  @override
  Future<void> saveConfig() async {
    await storageConfig.save();
  }

  @override
  Future<String> buildRepoPath(String directory) {
    return storageConfig.buildRepoPath(directory);
  }
}

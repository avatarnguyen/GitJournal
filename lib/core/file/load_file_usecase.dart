import 'dart:isolate';

import 'package:dart_git/blob_ctime_builder.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/file_mtime_builder.dart';
import 'package:gitjournal/core/file/file_storage.dart';
import 'package:gitjournal/error_reporting.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:tuple/tuple.dart';
import 'package:universal_io/io.dart' as io;

import 'file.dart';

typedef FillFileStorageParams
    = Tuple4<SendPort, String, BlobCTimeBuilder, FileMTimeBuilder>;

typedef FillFileStorageOutput
    = Tuple3<BlobCTimeBuilder, FileMTimeBuilder, GitHash>;

class LoadFileUseCase {
  static File loadFile(
    BlobCTimeBuilder blobCTimeBuilder,
    FileMTimeBuilder fileMTimeBuilder, {
    required String filePath,
    required String repoPath,
  }) {
    assert(!filePath.startsWith(path.separator));
    var fullFilePath = path.join(repoPath, filePath);

    assert(fileMTimeBuilder.map.isNotEmpty, "Trying to load $filePath");
    assert(blobCTimeBuilder.map.isNotEmpty, "Trying to load $filePath");

    var ioFile = io.File(fullFilePath);
    var stat = ioFile.statSync();
    if (stat.type == io.FileSystemEntityType.notFound) {
      throw Exception("File note found - $fullFilePath");
    }

    if (stat.type != io.FileSystemEntityType.file) {
      // FIXME: Better error!
      throw Exception('File is not file. Is ${stat.type}');
    }

    var mTimeInfo = fileMTimeBuilder.info(filePath);
    if (mTimeInfo == null) {
      Log.e("Failed to build path: $filePath");
      throw FileStorageCacheIncomplete(filePath);
    }

    var oid = mTimeInfo.hash;
    var modified = mTimeInfo.dt;

    assert(oid.isNotEmpty);

    var created = blobCTimeBuilder.cTime(oid);
    if (created == null) {
      throw Exception('when can this happen?');
    }

    return File(
      oid: oid,
      filePath: filePath,
      repoPath: repoPath,
      fileLastModified: stat.modified,
      created: created,
      modified: modified,
    );
  }

  static FillFileStorageOutput? fillFileStorage(FillFileStorageParams params) {
    var sendPort = params.item1;
    var repoPath = params.item2;
    var blobCTimeBuilder = params.item3;
    var fileMTimeBuilder = params.item4;

    var dateTime = DateTime.now();
    var visitor = MultiTreeEntryVisitor(
      [blobCTimeBuilder, fileMTimeBuilder],
      afterCommitCallback: (commit) {
        var commitDt = commit.author.date;
        if (commitDt.isBefore(dateTime)) {
          dateTime = commitDt;
          sendPort.send(dateTime);
        }
      },
    );

    var gitRepo = GitRepository.load(repoPath).getOrThrow();
    var headR = gitRepo.headHash();
    if (headR.isFailure) {
      if (headR.error is GitRefNotFound) {
        // No commits
        // fileStorageCacheReady = true;
        // notifyListeners();
        // FIXME: Send a signal saying its done
        return FillFileStorageOutput(
            blobCTimeBuilder, fileMTimeBuilder, GitHash.zero());
      }
      Log.e("Failed to fetch HEAD", result: headR);
      return null;
    }
    var head = headR.getOrThrow();
    Log.d("Got HEAD: $head");

    var result = gitRepo.visitTree(fromCommitHash: head, visitor: visitor);
    if (result.isFailure) {
      Log.e("Failed to build FileStorage cache", result: result);
      logException(result.exception!, result.stackTrace!);
    }

    return FillFileStorageOutput(blobCTimeBuilder, fileMTimeBuilder, head);
  }
}

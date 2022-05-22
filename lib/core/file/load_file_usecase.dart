import 'package:dart_git/blob_ctime_builder.dart';
import 'package:dart_git/file_mtime_builder.dart';
import 'package:gitjournal/core/file/file_storage.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart' as io;

import 'file.dart';

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
}

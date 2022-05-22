/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:isolate';

import 'package:dart_git/blob_ctime_builder.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/file_mtime_builder.dart';
import 'package:flutter/foundation.dart';
import 'package:gitjournal/core/file/load_file_usecase.dart';
import 'package:path/path.dart' as p;

import 'file.dart';

class FileStorage with ChangeNotifier {
  late final String repoPath;

  final BlobCTimeBuilder blobCTimeBuilder;
  final FileMTimeBuilder fileMTimeBuilder;

  var _dateTime = DateTime.now();
  DateTime get dateTime => _dateTime;

  var head = GitHash.zero();

  FileStorage({
    required String repoPath,
    required this.blobCTimeBuilder,
    required this.fileMTimeBuilder,
  }) {
    this.repoPath =
        repoPath.endsWith(p.separator) ? repoPath : repoPath + p.separator;
  }

  Future<Result<File>> load(String filePath) async {
    try {
      final resultFile = _loadFile(filePath);
      return Result(resultFile);
    } on Exception catch (error) {
      return Result.fail(error);
    }
  }

  File _loadFile(String filePath) {
    return LoadFileUseCase.loadFile(
      blobCTimeBuilder,
      fileMTimeBuilder,
      filePath: filePath,
      repoPath: repoPath,
    );
  }

  Future<void> fill() async {
    var rp = ReceivePort();
    var _ = rp.listen((d) {
      if (d is DateTime) {
        _dateTime = d;
        notifyListeners();
      }
    });

    var resp = await compute(
      LoadFileUseCase.fillFileStorage,
      FillFileStorageParams(
        rp.sendPort,
        repoPath,
        blobCTimeBuilder,
        fileMTimeBuilder,
      ),
    );
    rp.close();

    // FIXME: Handle this case of having an error!
    assert(resp != null);
    if (resp == null) return;

    blobCTimeBuilder.update(resp.item1);
    fileMTimeBuilder.update(resp.item2);
    head = resp.item3;
    notifyListeners();
  }

  @visibleForTesting
  static Future<FileStorage> fake(String rootFolder) async {
    assert(rootFolder.startsWith(p.separator));

    GitRepository.init(rootFolder).throwOnError();

    var blobVisitor = BlobCTimeBuilder();
    var mTimeBuilder = FileMTimeBuilder();

    var repo = GitRepository.load(rootFolder).getOrThrow();
    var result = repo.headHash();
    if (result.isSuccess) {
      var multi = MultiTreeEntryVisitor([blobVisitor, mTimeBuilder]);
      repo
          .visitTree(fromCommitHash: result.getOrThrow(), visitor: multi)
          .throwOnError();
    }
    // assert(!headHashR.isFailure, "Failed to get head hash");

    var repoPath = rootFolder.endsWith(p.separator)
        ? rootFolder
        : rootFolder + p.separator;

    return FileStorage(
      repoPath: repoPath,
      blobCTimeBuilder: blobVisitor,
      fileMTimeBuilder: mTimeBuilder,
    );
  }

  @visibleForTesting
  Future<Result<void>> reload() async {
    await fill();
    return Result(null);
  }
}

class FileStorageCacheIncomplete implements Exception {
  final String path;
  FileStorageCacheIncomplete(this.path);
}

/*
 * SPDX-FileCopyrightText: 2022 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:io' as io;

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/settings/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:universal_io/io.dart' as io;

import 'lib.dart';

Future<void> main() async {
  late String repoPath;

  final headHash = GitHash('c8a879a4a9c27abcc27a4d2ee2b2ba0aad5fc940');
  late GitJournalRepo repo;

  setUpAll(gjSetupAllTests);

  Future<void> _setup({
    GitHash? head,
    Map<String, Object> sharedPrefValues = const {},
  }) async {
    var td = await TestData.load(
      headHash: head ?? headHash,
      sharedPrefValues: sharedPrefValues,
    );

    repoPath = td.repoPath;
    repo = td.repo;
  }

  tearDown(() {
    // Most of repo's methods call an unawaited task to sync + reload
    // baseDir.deleteSync(recursive: true);
  });

  test('Outside Changes', () async {
    var extDir = await io.Directory.systemTemp.createTemp();
    var pref = <String, Object>{
      "${DEFAULT_ID}_storeInternally": false,
      "${DEFAULT_ID}_storageLocation": extDir.path,
    };

    await setupFixture(p.join(extDir.path, "test_data"), headHash);
    await _setup(sharedPrefValues: pref);
    var note = repo.rootFolder.getNoteWithSpec('1.md')!;
    io.File(note.fullFilePath).writeAsStringSync('foo');

    var repoManager = repo.repoManager;
    var newRepo = await repoManager
        .buildActiveRepository(loadFromCache: false, syncOnBoot: false)
        .getOrThrow();
    await newRepo.reloadNotes();

    var repoPath = newRepo.repoPath;
    var newNote = newRepo.rootFolder.getNoteWithSpec('1.md')!;
    expect(newNote.oid, isNot(note.oid));
    // expect(newNote.created, note.created);
    expect(newNote.body, 'foo');
    expect(newNote, isNot(note));

    var gitRepo = GitRepository.load(repoPath).getOrThrow();
    expect(gitRepo.headHash().getOrThrow(), isNot(headHash));

    var headCommit = gitRepo.headCommit().getOrThrow();
    expect(headCommit.parents.length, 1);
    expect(headCommit.parents[0], headHash);
  });

  test('Create folder', () async {
    await _setup();
    const folderName = 'test_removed';
    var rootFolder = repo.rootFolder;
    await repo.createFolder(rootFolder, folderName);

    final folder = rootFolder.getFolderWithSpec(folderName);
    expect(folder?.rootFolder, rootFolder);
    expect(folder?.folderName, folderName);

    final gitRepo = GitRepository.load(repoPath).getOrThrow();
    expect(gitRepo.headHash().getOrThrow(), isNot(headHash));

    var headCommit = gitRepo.headCommit().getOrThrow();
    expect(headCommit.parents.length, 1);
    expect(headCommit.parents[0], headHash);
  });

  // test('Remove folder', () async {
  //   await _setup();
  //   const folderName = 'test_removed';
  //   await repo.createFolder(_rootFolder!, folderName);
  //   //
  //   final folder = _rootFolder!.getFolderWithSpec(folderName);
  //   expect(folder?.rootFolder, _rootFolder!);
  //   expect(folder?.folderName, folderName);
  //
  //   final removeHeadHash = GitHash('7fc65b59170bdc91013eb56cdc65fa3307f2e7de');
  //   await _setup(head: removeHeadHash);
  //   await repo.removeFolder(folder!);
  //
  //   final removedFolder = _rootFolder!.getFolderWithSpec(folderName);
  //   expect(removedFolder, isNull);
  //
  //   final gitRepo = GitRepository.load(repoPath).getOrThrow();
  //   expect(gitRepo.headHash().getOrThrow(), isNot(headHash));
  //
  //   var headCommit = gitRepo.headCommit().getOrThrow();
  //   expect(headCommit.parents.length, 1);
  //   expect(headCommit.parents[0], isNot(removeHeadHash));
  // });
}

// Renames
// * Note - change content + rename
// * Note - saveNote fails because of 'x'
// move - ensure that destination cannot exist (and the git repo is in a good state after that)

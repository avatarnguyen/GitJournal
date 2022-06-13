import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitjournal/journal_folder.dart';
import 'package:gitjournal/repository.dart';

import 'lib.dart';

void main() {
  late GitJournalRepo repo;
  late JournalFolder journalFolder;
  late String repoPath;

  final headHash = GitHash('c8a879a4a9c27abcc27a4d2ee2b2ba0aad5fc940');

  Future<void> _setupWithTestData({
    GitHash? head,
    Map<String, Object> sharedPrefValues = const {},
  }) async {
    var gitHash = head ?? headHash;
    var testData = await TestData.load(
      headHash: gitHash,
      sharedPrefValues: sharedPrefValues,
    );

    debugPrint('Head Hash: $gitHash');
    debugPrint('Test Data Instance: ${testData.hashCode}');

    repoPath = testData.repoPath;
    repo = testData.repo;
    journalFolder = JournalFolder(repo, repo.gitRepo, repo.notesFolderConfig);
  }

  setUpAll(gjSetupAllTests);
  setUp(_setupWithTestData);

  group('Folder', () {
    test('should Create new folder successfully', () async {
      // await _setup();
      const folderName = 'test_removed';
      var rootFolder = repo.rootFolder;
      await journalFolder.create(rootFolder, folderName);

      final folder = rootFolder.getFolderWithSpec(folderName);
      expect(folder?.rootFolder, rootFolder);
      expect(folder?.folderName, folderName);

      final gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), isNot(headHash));

      var headCommit = gitRepo.headCommit().getOrThrow();
      expect(headCommit.parents.length, 1);
      expect(headCommit.parents[0], headHash);
    });

    test('should create and then remove the created folder successfully',
        () async {
      // arrange
      final removeHeadHash =
          GitHash('7fc65b59170bdc91013eb56cdc65fa3307f2e7de');
      await _setupWithTestData(head: removeHeadHash);
      const folderName = 'test_removed';
      final _rootFolder = repo.rootFolder;
      await journalFolder.create(_rootFolder, folderName);

      final folder = _rootFolder.getFolderWithSpec(folderName);
      expect(folder?.rootFolder, _rootFolder);
      expect(folder?.folderName, folderName);

      // act
      await journalFolder.remove(folder!);

      // assert
      final removedFolder = _rootFolder.getFolderWithSpec(folderName);
      expect(removedFolder, isNull);

      final gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), isNot(headHash));

      var headCommit = gitRepo.headCommit().getOrThrow();
      expect(headCommit.parents.length, 1);
      expect(headCommit.parents[0], isNot(removeHeadHash));
    });
  });
}

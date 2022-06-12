import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitjournal/core/notes/note.dart';
import 'package:gitjournal/journal_note.dart';
import 'package:gitjournal/repository.dart';

import 'lib.dart';

void main() {
  late GitJournalRepo repo;
  late JournalNote journalNote;
  late String repoPath;

  final headHash = GitHash('c8a879a4a9c27abcc27a4d2ee2b2ba0aad5fc940');

  Future<void> _setupWithTestData({
    GitHash? head,
    Map<String, Object> sharedPrefValues = const {},
  }) async {
    var testData = await TestData.load(
      headHash: head ?? headHash,
      sharedPrefValues: sharedPrefValues,
    );

    print('Test Data Instance: ${testData.hashCode}');

    repoPath = testData.repoPath;
    repo = testData.repo;
    journalNote = JournalNote(repo, repo.gitRepo);
  }

  setUpAll(gjSetupAllTests);
  setUp(_setupWithTestData);

  group('Rename Note ', () {
    test('should rename note successfully', () async {
      final allNotesBefore = repo.rootFolder.getAllNotes();
      //arrange
      final note =
          repo.rootFolder.notes.firstWhere((n) => n.fileName == '1.md');
      // act
      const newPath = '1_new.md';
      var _result = await journalNote.rename(note, newPath).getOrThrow();
      final allNotesAfter = repo.rootFolder.getAllNotes();
      // assert
      expect(_result.filePath, newPath);
      expect(allNotesBefore, allNotesAfter);
    });

    test('should not have the same GitHash after rename', () async {
      // arrange
      final note =
          repo.rootFolder.notes.firstWhere((n) => n.fileName == '1.md');
      const newPath = '1_new.md';
      await journalNote.rename(note, newPath).getOrThrow();

      var gitRepo = GitRepository.load(repoPath).getOrThrow();

      var gitHash = gitRepo.headHash().getOrThrow();
      print('Git Repo Hash: $gitHash');
      expect(gitHash, isNot(headHash));

      var headCommit = gitRepo.headCommit().getOrThrow();
      print('Head Commit: $headCommit');
      expect(headCommit.parents.length, 1);
      expect(headCommit.parents[0], headHash);
    });

    test('should Change File Type', () async {
      final note =
          repo.rootFolder.notes.firstWhere((n) => n.fileName == '1.md');

      const newPath = '1_new.txt';
      final result = await journalNote.rename(note, newPath).getOrThrow();

      expect(result.filePath, newPath);
      expect(result.fileFormat, NoteFileFormat.Txt);
      expect(repo.rootFolder.getAllNotes().length, 3);
    });

    test('should throw exception if destination exists', () async {
      var note = repo.rootFolder.notes.firstWhere((n) => n.fileName == '1.md');

      var newPath = "2.md";
      var result = await journalNote.rename(note, newPath);
      expect(result.isFailure, true);
      expect(result.error, isA<Exception>());

      var gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), headHash);
    });
  });
}

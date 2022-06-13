import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/notes/note.dart';
import 'package:gitjournal/journal_note.dart';
import 'package:gitjournal/repository.dart';
import 'package:universal_io/io.dart' as io;

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

  group('Update Note ', () {
    test('updateNote - Basic', () async {
      var note = repo.rootFolder.notes.firstWhere((n) => n.fileName == '1.md');

      var toNote = note.resetOid();
      toNote = toNote.copyWith(body: '11');
      toNote = await journalNote.update(note, toNote).getOrThrow();

      var gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), isNot(headHash));

      var headCommit = gitRepo.headCommit().getOrThrow();
      expect(headCommit.parents.length, 1);
      expect(headCommit.parents[0], headHash);

      var contents = io.File(toNote.fullFilePath).readAsStringSync();
      expect(contents, '11\n');
    });

    test('updateNote - Fails', () async {
      var note = repo.rootFolder.getNoteWithSpec('f1/3.md')!;

      var toNote = note.resetOid();
      toNote = toNote.copyWith(body: "doesn't matter");
      io.Directory(note.parent.fullFolderPath).deleteSync(recursive: true);

      var result = await journalNote.update(note, toNote);
      expect(result.isFailure, true);
      expect(result.error, isA<Exception>());

      var gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), headHash);
    });

    // test('updateNote - created metadata stays the same', () async {
    //   var headHash = GitHash('38e8c9150c0c004c9f72221ac7c19cf770575545');
    //   await _setup(head: headHash);
    //
    //   var note = repo.rootFolder.getNoteWithSpec('doc.md')!;
    //   var toNote = note.resetOid();
    //
    //   expect(toNote.created, note.created);
    //   toNote = await repo.updateNote(note, toNote).getOrThrow();
    //
    //   var gitRepo = GitRepository.load(repoPath).getOrThrow();
    //   expect(gitRepo.headHash().getOrThrow(), isNot(headHash));
    //
    //   var headCommit = gitRepo.headCommit().getOrThrow();
    //   expect(headCommit.parents.length, 1);
    //   expect(headCommit.parents[0], headHash);
    //
    //   expect(toNote.created, note.created);
    //   expect(toNote.modified.isAfter(note.modified), true);
    // });

    // test('Add a tag', () async {
    //   var headHash = GitHash('7fc65b59170bdc91013eb56cdc65fa3307f2e7de');
    //   await _setup(head: headHash);
    //
    //   var note = repo.rootFolder.getNoteWithSpec('doc.md')!;
    //   var updatedNote = note.resetOid();
    //   updatedNote = updatedNote.copyWith(tags: {"Foo"}.lock);
    //
    //   var r = await repo.updateNote(note, updatedNote);
    //   expect(r.isSuccess, true);
    //   expect(r.isFailure, false);
    //
    //   var note2 = r.getOrThrow();
    //   expect(note2.tags, {"Foo"});
    //   expect(note2.data.props.containsKey("tags"), true);
    //
    //   var gitRepo = GitRepository.load(repoPath).getOrThrow();
    //   expect(gitRepo.headHash().getOrThrow(), isNot(headHash));
    //
    //   var headCommit = gitRepo.headCommit().getOrThrow();
    //   expect(headCommit.parents.length, 1);
    //   expect(headCommit.parents[0], headHash);
    // });
  });

  group('Add Note', () {
    test('should create new note locally and on git', () async {
      var note = Note.newNote(
        repo.rootFolder,
        fileFormat: NoteFileFormat.Markdown,
      );

      note = note.copyWith(body: '7');
      note = note.copyWithFileName('7.md');
      note = await journalNote.addNote(note).getOrThrow();

      var gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), isNot(headHash));

      var headCommit = gitRepo.headCommit().getOrThrow();
      expect(headCommit.parents.length, 1);
      expect(headCommit.parents[0], headHash);

      var contents = io.File(note.fullFilePath).readAsStringSync();
      expect(contents.contains('7\n'), true);
    });

    test('should throw exception if create operation failed', () async {
      var folder = repo.rootFolder.getFolderWithSpec('f1')!;
      var note = Note.newNote(folder, fileFormat: NoteFileFormat.Markdown);

      note = note.copyWith(body: '7');
      note = note.copyWithFileName('7.md');

      io.Directory(folder.fullFolderPath).deleteSync(recursive: true);
      var result = await journalNote.addNote(note);
      expect(result.isFailure, true);
      expect(result.error, isA<Exception>());

      var gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), headHash);
    });
  });

  group('Move Note ', () {
    test('Move - Note from root to Folder', () async {
      var note = repo.rootFolder.getNoteWithSpec('1.md')!;
      var folder = repo.rootFolder.getFolderWithSpec('f1')!;

      var r = await journalNote.move(note, folder);
      expect(r.isSuccess, true);
      expect(r.isFailure, false);

      var gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), isNot(headHash));

      var headCommit = gitRepo.headCommit().getOrThrow();
      expect(headCommit.parents.length, 1);
      expect(headCommit.parents[0], headHash);

      var root = repo.rootFolder;
      expect(root.getNoteWithSpec('1.md'), null);
      expect(root.getNoteWithSpec('f1/1.md'), isNotNull);
    });

    test('Move - Note from Folder to Root', () async {
      var note = repo.rootFolder.getNoteWithSpec('f1/3.md')!;
      var folder = repo.rootFolder;

      var r = await journalNote.move(note, folder);
      expect(r.isSuccess, true);
      expect(r.isFailure, false);

      var gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), isNot(headHash));

      var headCommit = gitRepo.headCommit().getOrThrow();
      expect(headCommit.parents.length, 1);
      expect(headCommit.parents[0], headHash);

      var root = repo.rootFolder;
      expect(root.getNoteWithSpec('f1/3.md'), null);
      expect(root.getNoteWithSpec('3.md'), isNotNull);
    });

    test('Move - To New Folder', () async {
      var note = repo.rootFolder.getNoteWithSpec('1.md')!;
      var folder = repo.rootFolder.getOrBuildFolderWithSpec('f2');
      folder.create();

      var r = await journalNote.move(note, folder);
      expect(r.isSuccess, true);
      expect(r.isFailure, false);

      var gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), isNot(headHash));

      var headCommit = gitRepo.headCommit().getOrThrow();
      expect(headCommit.parents.length, 1);
      expect(headCommit.parents[0], headHash);

      var root = repo.rootFolder;
      expect(root.getNoteWithSpec('1.md'), null);
      expect(root.getNoteWithSpec('f2/1.md'), isNotNull);
    });

    test('Move - To New Folder Failure', () async {
      var note = repo.rootFolder.getNoteWithSpec('1.md')!;
      var folder = repo.rootFolder.getOrBuildFolderWithSpec('f2');

      var r = await journalNote.move(note, folder);
      expect(r.isFailure, true);

      var gitRepo = GitRepository.load(repoPath).getOrThrow();
      expect(gitRepo.headHash().getOrThrow(), headHash);

      var root = repo.rootFolder;
      expect(root.getNoteWithSpec('1.md'), isNotNull);
      expect(root.getNoteWithSpec('f2/1.md'), isNull);
    });

    // test('Move - From one folder to another folder', () async {
    //   var headHash = GitHash('7fc65b59170bdc91013eb56cdc65fa3307f2e7de');
    //   await _setup(head: headHash);
    //   var note = repo.rootFolder.getNoteWithSpec('f1/3.md')!;
    //   var folder = repo.rootFolder.getFolderWithSpec('f2')!;
    //
    //   var r = await repo.moveNote(note, folder);
    //   expect(r.isSuccess, true);
    //   expect(r.isFailure, false);
    //
    //   var gitRepo = GitRepository.load(repoPath).getOrThrow();
    //   expect(gitRepo.headHash().getOrThrow(), isNot(headHash));
    //
    //   var headCommit = gitRepo.headCommit().getOrThrow();
    //   expect(headCommit.parents.length, 1);
    //   expect(headCommit.parents[0], headHash);
    //
    //   var root = repo.rootFolder;
    //   expect(root.getNoteWithSpec('f1/3.md'), null);
    //   expect(root.getNoteWithSpec('f2/3.md'), isNotNull);
    // });
  });
}

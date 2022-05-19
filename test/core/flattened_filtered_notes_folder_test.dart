/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:math';

import 'package:dart_git/dart_git.dart';
import 'package:gitjournal/core/file/file_storage.dart';
import 'package:gitjournal/core/folder/flattened_filtered_notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder_config.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/note_storage.dart';
import 'package:gitjournal/core/notes/note.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';
import 'package:universal_io/io.dart' as io;

import '../lib.dart';

void main() {
  setUpAll(gjSetupAllTests);

  var random = Random(DateTime.now().millisecondsSinceEpoch);

  String _getRandomFilePath(String basePath) {
    while (true) {
      var filePath = p.join(basePath, "${random.nextInt(1000)}.md");
      if (io.File(filePath).existsSync()) {
        continue;
      }

      return filePath;
    }
  }

  group('Flattened Notes Folder Test', () {
    late io.Directory tempDir;
    late String repoPath;
    late NotesFolderFS rootFolder;
    late NotesFolderConfig config;
    late FileStorage fileStorage;

    setUp(() async {
      tempDir = await io.Directory.systemTemp.createTemp('__fnft__');
      repoPath = tempDir.path + p.separator;

      SharedPreferences.setMockInitialValues({});
      config = NotesFolderConfig('', await SharedPreferences.getInstance());
      fileStorage = await FileStorage.fake(repoPath);

      rootFolder = NotesFolderFS.root(config, fileStorage);

      for (var i = 0; i < 3; i++) {
        var fp = _getRandomFilePath(rootFolder.fullFolderPath);
        var note = Note.newNote(rootFolder,
            fileName: p.basename(fp), fileFormat: NoteFileFormat.Markdown);
        note = note.copyWith(
          modified: DateTime(2020, 1, 10 + (i * 2)),
          body: "$i\n",
        );
        note = await NoteStorage.save(note).getOrThrow();
      }

      io.Directory(p.join(repoPath, "sub1")).createSync();
      io.Directory(p.join(repoPath, "sub1", "p1")).createSync();
      io.Directory(p.join(repoPath, "sub2")).createSync();

      var sub1Folder = NotesFolderFS(rootFolder, "sub1", config);
      for (var i = 0; i < 2; i++) {
        var fp = _getRandomFilePath(sub1Folder.fullFolderPath);
        var note = Note.newNote(
          sub1Folder,
          fileName: p.basename(fp),
          fileFormat: NoteFileFormat.Markdown,
        );

        note = note.copyWith(
          modified: DateTime(2020, 1, 10 + (i * 2)),
          body: "sub1-$i\n",
        );
        note = await NoteStorage.save(note).getOrThrow();
      }

      var sub2Folder = NotesFolderFS(rootFolder, "sub2", config);
      for (var i = 0; i < 2; i++) {
        var fp = _getRandomFilePath(sub2Folder.fullFolderPath);
        var note = Note.newNote(sub2Folder,
            fileName: p.basename(fp), fileFormat: NoteFileFormat.Markdown);

        note = note.copyWith(
          modified: DateTime(2020, 1, 10 + (i * 2)),
          body: "sub2-$i\n",
        );
        note = await NoteStorage.save(note).getOrThrow();
      }

      var p1Folder = NotesFolderFS(sub1Folder, p.join("sub1", "p1"), config);
      for (var i = 0; i < 2; i++) {
        var fp = _getRandomFilePath(p1Folder.fullFolderPath);
        var note = Note.newNote(p1Folder,
            fileName: p.basename(fp), fileFormat: NoteFileFormat.Markdown);

        note = note.copyWith(
          modified: DateTime(2020, 1, 10 + (i * 2)),
          body: "p1-$i\n",
        );
        note = await NoteStorage.save(note).getOrThrow();
      }

      var repo = GitRepository.load(repoPath).getOrThrow();
      repo
          .commit(
            message: "Prepare Test Env",
            author: GitAuthor(name: 'Name', email: "name@example.com"),
            addAll: true,
          )
          .throwOnError();

      await rootFolder.fileStorage.reload().throwOnError();

      expect(fileStorage.blobCTimeBuilder.map, isNotEmpty);
      expect(fileStorage.fileMTimeBuilder.map, isNotEmpty);

      await rootFolder.loadRecursively();
      expect(rootFolder.notes, isNotEmpty);
    });

    tearDown(() async {
      tempDir.deleteSync(recursive: true);
    });

    test('Basic Filter should work', () async {
      final _flattenedFilteredNotesFolder =
          await FlattenedFilteredNotesFolder.load(
        rootFolder,
        title: "foo",
        filter: (Note note) async => note.body.contains('sub'),
      );
      expect(_flattenedFilteredNotesFolder.subFolders.length, 0);
      expect(_flattenedFilteredNotesFolder.notes.length, 4);

      final notes = List<Note>.from(_flattenedFilteredNotesFolder.notes);
      notes.sort((Note n1, Note n2) => n1.body.compareTo(n2.body));

      expect(notes[0].body, "sub1-0\n");
      expect(notes[1].body, "sub1-1\n");
      expect(notes[2].body, "sub2-0\n");
      expect(notes[3].body, "sub2-1\n");
    });

    test('should remove a note from folder', () async {
      // arrange
      final _flattenedFilteredNotesFolder =
          await FlattenedFilteredNotesFolder.load(
        rootFolder,
        title: "foo",
        filter: (Note note) async => note.body.contains('sub'),
      );
      expect(_flattenedFilteredNotesFolder.notes.length, 4);

      // act
      rootFolder.subFoldersFS.first
          .remove(_flattenedFilteredNotesFolder.notes.first);

      // assert
      expect(_flattenedFilteredNotesFolder.notes.length, 3);
    });

    test('should add a new note to a subfolder', () async {
      // arrange
      final _flattenedFilteredNotesFolder =
          await FlattenedFilteredNotesFolder.load(
        rootFolder,
        title: "foo",
        filter: (Note note) async => note.body.contains('sub'),
      );
      expect(_flattenedFilteredNotesFolder.notes.length, 4);

      // act
      final firstSubfolder = rootFolder.subFoldersFS.first;
      final fp = _getRandomFilePath(firstSubfolder.fullFolderPath);
      var note = Note.newNote(
        firstSubfolder,
        fileName: p.basename(fp),
        fileFormat: NoteFileFormat.Markdown,
      );

      note = note.copyWith(
        modified: DateTime.now(),
        body: "sub_test",
      );
      note = await NoteStorage.save(note).getOrThrow();
      firstSubfolder.add(note);

      await firstSubfolder.fileStorage.reload().throwOnError();
      expect(_flattenedFilteredNotesFolder.notes.length, 5);
    });

    // TODO
    // Test loading it incrementally
    // Test renaming a file
  });
}

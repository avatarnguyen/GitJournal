import 'dart:math';

import 'package:dart_git/dart_git.dart';
import 'package:gitjournal/core/file/file_storage.dart';
import 'package:gitjournal/core/folder/filtered_notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/note_storage.dart';
import 'package:gitjournal/core/notes/note.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';
import 'package:universal_io/io.dart' as io;

import '../../lib.dart';

void main() {
  setUpAll(gjSetupAllTests);

  var random = Random(DateTime.now().millisecondsSinceEpoch);

  String _getRandomFilePath(String basePath) {
    while (true) {
      var filePath = path.join(basePath, "${random.nextInt(1000)}.md");
      if (io.File(filePath).existsSync()) {
        continue;
      }

      return filePath;
    }
  }

  group("FilteredNotes Folder Test", () {
    late io.Directory tempDir;
    late String repoPath;
    late NotesFolderFS rootFolder;
    late NotesFolderConfig config;
    late FileStorage fileStorage;

    setUp(() async {
      tempDir = await io.Directory.systemTemp
          .createTemp('__filtered_notes_folder_test__');
      repoPath = tempDir.path + path.separator;

      SharedPreferences.setMockInitialValues({});
      config = NotesFolderConfig('', await SharedPreferences.getInstance());
      fileStorage = await FileStorage.fake(repoPath);

      rootFolder = NotesFolderFS.root(config, fileStorage);

      for (var i = 0; i < 3; i++) {
        var fp = _getRandomFilePath(rootFolder.fullFolderPath);
        var note = Note.newNote(rootFolder,
            fileName: path.basename(fp), fileFormat: NoteFileFormat.Markdown);
        note = note.copyWith(
          modified: DateTime(2020, 1, 10 + (i * 2)),
          body: "$i\n",
        );
        note = await NoteStorage.save(note).getOrThrow();
      }

      io.Directory(path.join(repoPath, "sub1")).createSync();
      io.Directory(path.join(repoPath, "sub1", "p1")).createSync();
      io.Directory(path.join(repoPath, "sub2")).createSync();

      var sub1Folder = NotesFolderFS(rootFolder, "sub1", config);
      for (var i = 0; i < 2; i++) {
        var fp = _getRandomFilePath(sub1Folder.fullFolderPath);
        var note = Note.newNote(sub1Folder,
            fileName: path.basename(fp), fileFormat: NoteFileFormat.Markdown);

        note = note.copyWith(
          modified: DateTime(2020, 1, 10 + (i * 2)),
          body: "sub1-$i\n",
        );
        print("Note: $note");

        note = await NoteStorage.save(note).getOrThrow();
      }

      var sub2Folder = NotesFolderFS(rootFolder, "sub2", config);
      for (var i = 0; i < 2; i++) {
        var fp = _getRandomFilePath(sub2Folder.fullFolderPath);
        var note = Note.newNote(sub2Folder,
            fileName: path.basename(fp), fileFormat: NoteFileFormat.Markdown);

        note = note.copyWith(
          modified: DateTime(2020, 1, 10 + (i * 2)),
          body: "sub2-$i\n",
        );
        note = await NoteStorage.save(note).getOrThrow();
      }

      var p1Folder = NotesFolderFS(sub1Folder, path.join("sub1", "p1"), config);
      for (var i = 0; i < 2; i++) {
        var fp = _getRandomFilePath(p1Folder.fullFolderPath);
        var note = Note.newNote(p1Folder,
            fileName: path.basename(fp), fileFormat: NoteFileFormat.Markdown);

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

      await rootFolder.loadRecursively();
    });

    tearDown(() async {
      tempDir.deleteSync(recursive: true);
    });

    test('root folder and file storage loaded', () {
      expect(fileStorage.blobCTimeBuilder.map, isNotEmpty);
      expect(fileStorage.fileMTimeBuilder.map, isNotEmpty);

      expect(rootFolder.notes, isNotEmpty);
    });

    test('should instantiate new filtered notes folder successfully', () async {
      final filteredNoteFolders = await FilteredNotesFolder.load(
        rootFolder,
        title: "foo",
        filter: (Note note) async => true,
      );
      expect(filteredNoteFolders.subFolders.length, 2);
      expect(filteredNoteFolders.notes.length, 3);

      final _subFolders =
          List<NotesFolder>.from(filteredNoteFolders.subFolders);
      expect(_subFolders[0].name, "sub1");
      expect(_subFolders[1].name, "sub2");
    });
  });
}

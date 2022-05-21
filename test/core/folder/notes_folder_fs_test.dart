import 'dart:math';

import 'package:dart_git/dart_git.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitjournal/core/file/file_storage.dart';
import 'package:gitjournal/core/folder/notes_folder_config.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/note_storage.dart';
import 'package:gitjournal/core/notes/note.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
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

  Future<void> _addNewNoteToSubFolder(
    NotesFolderFS folder,
    String bodyPrefix,
  ) async {
    for (var i = 0; i < 2; i++) {
      var fp = _getRandomFilePath(folder.fullFolderPath);
      var note = Note.newNote(
        folder,
        fileName: path.basename(fp),
        fileFormat: NoteFileFormat.Markdown,
      );

      note = note.copyWith(
        modified: DateTime(2020, 1, 10 + (i * 2)),
        body: "$bodyPrefix-$i\n",
      );
      note = await NoteStorage.save(note).getOrThrow();
    }
  }

  group('Notes Folder FS', () {
    late io.Directory tempDir;
    late String repoPath;
    late NotesFolderConfig config;
    late FileStorage fileStorage;
    late NotesFolderFS rootFolder;

    setUp(() async {
      tempDir =
          await io.Directory.systemTemp.createTemp('__notes_folder_fs_test__');
      repoPath = tempDir.path + path.separator;

      SharedPreferences.setMockInitialValues({});
      config = NotesFolderConfig('', await SharedPreferences.getInstance());
      fileStorage = await FileStorage.fake(repoPath);

      rootFolder = NotesFolderFS.root(config, fileStorage);

      await _addNewNoteToSubFolder(rootFolder, "");
      await _addNewNoteToSubFolder(rootFolder, ".test_ignore_file");

      io.Directory(path.join(repoPath, "sub1")).createSync();
      io.Directory(path.join(repoPath, "sub1", "p1")).createSync();
      io.Directory(path.join(repoPath, "sub2")).createSync();

      final sub1Folder = NotesFolderFS(rootFolder, "sub1", config);
      await _addNewNoteToSubFolder(sub1Folder, "sub1");

      final sub2Folder = NotesFolderFS(rootFolder, "sub2", config);
      await _addNewNoteToSubFolder(sub2Folder, "sub2");

      final p1Folder =
          NotesFolderFS(sub1Folder, path.join("sub1", "p1"), config);
      await _addNewNoteToSubFolder(p1Folder, "p1");

      var repo = GitRepository.load(repoPath).getOrThrow();
      repo
          .commit(
            message: "Prepare Test Env",
            author: GitAuthor(name: 'Name', email: "name@example.com"),
            addAll: true,
          )
          .throwOnError();

      await rootFolder.fileStorage.reload().throwOnError();
    });

    tearDown(() async {
      tempDir.deleteSync(recursive: true);
    });

    test('should load all notes and sub folders successfully', () async {
      await rootFolder.loadRecursively();
      expect(fileStorage.blobCTimeBuilder.map, isNotEmpty);
      expect(fileStorage.fileMTimeBuilder.map, isNotEmpty);
      expect(rootFolder.notes, isNotEmpty);
      // subfolder and subfolderfs return the same thing only in different type
      expect(rootFolder.subFoldersFS, isNotEmpty);
      expect(rootFolder.subFolders, isNotEmpty);
    });
  });
}

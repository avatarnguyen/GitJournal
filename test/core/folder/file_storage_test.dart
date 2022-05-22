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

  group('File Storage -', () {
    late io.Directory tempDir;
    late String repoPath;
    late NotesFolderConfig config;
    late FileStorage fileStorage;
    late NotesFolderFS rootFolder;

    setUp(() async {
      tempDir = io.Directory.systemTemp.createTempSync('__file_storage_test__');
      repoPath = tempDir.path + path.separator;

      SharedPreferences.setMockInitialValues({});
      config = NotesFolderConfig('', await SharedPreferences.getInstance());

      fileStorage = await FileStorage.fake(repoPath);
      rootFolder = NotesFolderFS.root(config, fileStorage);

      await _addNewNoteToSubFolder(rootFolder, "");
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

    test('should construct a new file storage instance', () async {
      await rootFolder.loadRecursively();
      expect(fileStorage.blobCTimeBuilder.map, isNotEmpty);
      expect(fileStorage.fileMTimeBuilder.map, isNotEmpty);
      expect(rootFolder.notes, isNotEmpty);
    });

    test('should load results from file storage', () async {
      // act
      await rootFolder.loadRecursively();
      final notePath = rootFolder.notes.first.filePath;
      print('path: $notePath');
      final _result = await fileStorage.load(notePath);
      print('Result: ${_result.data}');

      // assert
      expect(_result, isNotNull);
      expect(_result.data, isNotNull);
    });
  });
}

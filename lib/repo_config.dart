import 'package:gitjournal/core/folder/notes_folder_config.dart';
import 'package:gitjournal/settings/git_config.dart';
import 'package:gitjournal/settings/settings.dart';
import 'package:gitjournal/settings/storage_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RepoConfig {
  final String id;
  final SharedPreferences pref;

  late GitConfig _gitConfig;
  late Settings _settings;
  late StorageConfig _storageConfig;
  late NotesFolderConfig _folderConfig;

  RepoConfig(this.id, this.pref) {
    _storageConfig = StorageConfig(id, pref);
    _storageConfig.load();

    _folderConfig = NotesFolderConfig(id, pref);
    _folderConfig.load();

    _gitConfig = GitConfig(id, pref);
    _gitConfig.load();

    _settings = Settings(id, pref);
    _settings.load();
  }

  StorageConfig get storageConfig => _storageConfig;
  NotesFolderConfig get folderConfig => _folderConfig;
  GitConfig get gitConfig => _gitConfig;
  Settings get settings => _settings;
}

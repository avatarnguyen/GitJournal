/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder_notifier.dart';
import 'package:gitjournal/core/note.dart';
import 'package:synchronized/synchronized.dart';

typedef NotesFilter = Future<bool> Function(Note note);

class FilteredNotesFolder extends NotesFolderNotifier implements NotesFolder {
  final NotesFolder folder;
  final NotesFilter filter;
  final String title;

  final _lock = Lock();

  final _notes = <Note>[];

  FilteredNotesFolder._internal(this.folder, this.title, this.filter);

  static Future<FilteredNotesFolder> load(
    NotesFolder parentFolder, {
    required String title,
    required NotesFilter filter,
  }) async {
    var folder = FilteredNotesFolder._internal(parentFolder, title, filter);
    await folder._addFolder(parentFolder);

    return folder;
  }

  Future<void> _addFolder(NotesFolder folder) async {
    _addChangeNotifierListener(folder);
    await _addIndividualNotes(folder);
  }

  void _addChangeNotifierListener(NotesFolder folder) {
    _addNoteListenerCallback(folder);
  }

  void _addNoteListenerCallback(NotesFolder folder) {
    folder.addNoteAddedListener(_noteAdded);
    folder.addNoteRemovedListener(_noteRemoved);
    folder.addNoteModifiedListener(_noteModified);
    folder.addNoteRenameListener(_noteRenamed);
  }

  Future<void> _addIndividualNotes(NotesFolder folder) async {
    for (var note in folder.notes) {
      await _noteAdded(-1, note);
    }
  }

  Future<void> _noteAdded(int _, Note note) async {
    var shouldAllow = await filter(note);
    // print("Filter shouldAllow: $shouldAllow");
    if (!shouldAllow) {
      return;
    }

    await _lock.synchronized(() {
      // The filtering is async so we need to check again
      var contain = _notes.indexWhere((n) => n.filePath == note.filePath) != -1;
      if (contain) {
        notifyNoteModified(
          -1,
          note,
          noteModifiedListeners,
        );
        return;
      }
      _notes.add(note);
      notifyNoteAdded(-1, note, noteAddedListeners);
    });
  }

  Future<void> _noteRemoved(int _, Note note) async {
    await _lock.synchronized(() {
      var i = _notes.indexWhere((n) => n.filePath == note.filePath);
      // assert(i != -1);
      if (i == -1) {
        return;
      }

      var _ = _notes.removeAt(i);
      notifyNoteRemoved(-1, note, noteRemovedListeners);
    });
  }

  Future<void> _noteModified(int _, Note note) async {
    return await _lock.synchronized(() async {
      var contain = _notes.indexWhere((n) => n.filePath == note.filePath) != -1;
      if (contain) {
        if (await filter(note)) {
          notifyNoteModified(-1, note, noteModifiedListeners);
        } else {
          _noteRemoved(-1, note);
        }
      } else {
        if (await filter(note)) {
          _notes.add(note);
          notifyNoteAdded(-1, note, noteAddedListeners);
        }
      }
    });
  }

  void _noteRenamed(int _, Note note, String oldPath) {
    notifyNoteRenamed(-1, note, oldPath, noteRenameListeners);
  }

  @override
  List<Note> get notes => _notes;

  @override
  List<NotesFolder> get subFolders => folder.subFolders;

  @override
  bool get hasNotes => _notes.isNotEmpty;

  @override
  bool get isEmpty => _notes.isEmpty;

  @override
  NotesFolder? get parent => null;

  @override
  NotesFolder? get fsFolder => folder.fsFolder;

  @override
  String get name => title;

  @override
  String get publicName => title;

  @override
  NotesFolderConfig get config => folder.config;
}

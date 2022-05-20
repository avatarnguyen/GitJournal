/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/foundation.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/folder/notes_folder_notifier.dart';

import '../note.dart';
import 'notes_folder_config.dart';

export 'notes_folder_config.dart';
export 'notes_folder_observer.dart';

abstract class NotesFolder extends NotesFolderObserver {
  bool get isEmpty;
  bool get hasNotes;
  String get name;
  String get publicName;

  List<Note> get notes;
  List<NotesFolder> get subFolders;
  NotesFolder? get parent;
  NotesFolder? get fsFolder;

  NotesFolderConfig get config;

  void addListener(void Function() folderChanged);
  void removeListener(void Function() folderChanged);
}

abstract class NotesFolderObserver {
  // Folder ObserverList
  ObserverList<void Function(int, NotesFolder)>? get folderAddedListeners;
  ObserverList<void Function(int, NotesFolder)>? get folderRemovedListeners;
  ObserverList<void Function(NotesFolderFS, String)>?
      get thisFolderRenamedListeners;
  // Notes ObserverList
  ObserverList<void Function(int, Note)>? get noteAddedListeners;
  ObserverList<void Function(int, Note)>? get noteRemovedListeners;
  ObserverList<void Function(int, Note)>? get noteModifiedListeners;
  ObserverList<void Function(int, Note, String)>? get noteRenameListeners;

  void addNoteAddedListener(NoteNotificationCallback listener);

  void removeNoteAddedListener(NoteNotificationCallback listener);

  void addNoteRemovedListener(NoteNotificationCallback listener);

  void removeNoteRemovedListener(NoteNotificationCallback listener);

  void addNoteModifiedListener(NoteNotificationCallback listener);

  void removeNoteModifiedListener(NoteNotificationCallback listener);

  void addNoteRenameListener(NoteRenamedCallback listener);

  void removeNoteRenameListener(NoteRenamedCallback listener);

  void addFolderRemovedListener(FolderNotificationCallback listener);

  void removeFolderRemovedListener(FolderNotificationCallback listener);

  void addFolderAddedListener(FolderNotificationCallback listener);

  void removeFolderAddedListener(FolderNotificationCallback listener);

  void addThisFolderRenamedListener(FolderRenamedCallback listener);

  void removeThisFolderRenamedListener(FolderRenamedCallback listener);
}

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

abstract class NotesFolder with NotesFolderObserver, NotesObserver {
  bool get isEmpty;
  bool get hasNotes;
  String get name;
  String get publicName;

  List<Note> get notes;
  List<NotesFolder> get subFolders;
  NotesFolder? get parent;
  NotesFolder? get fsFolder;

  NotesFolderConfig get config;
}

class NotesObserver {
  final ObserverList<void Function(int, Note)>? _noteAddedListeners =
      ObserverList<NoteNotificationCallback>();
  final ObserverList<void Function(int, Note)>? _noteRemovedListeners =
      ObserverList<NoteNotificationCallback>();
  final ObserverList<void Function(int, Note)>? _noteModifiedListeners =
      ObserverList<NoteNotificationCallback>();
  final ObserverList<void Function(int, Note, String)>? _noteRenameListeners =
      ObserverList<NoteRenamedCallback>();

  void addNoteAddedListener(NoteNotificationCallback listener) {
    if (_noteAddedListeners != null) {
      _noteAddedListeners!.add(listener);
    }
  }

  void removeNoteAddedListener(NoteNotificationCallback listener) {
    if (_noteAddedListeners != null) {
      assert(_noteAddedListeners!.contains(listener));
      var _ = _noteAddedListeners!.remove(listener);
    }
  }

  void addNoteRemovedListener(NoteNotificationCallback listener) {
    if (_noteRemovedListeners != null) {
      _noteRemovedListeners!.add(listener);
    }
  }

  void removeNoteRemovedListener(NoteNotificationCallback listener) {
    if (_noteRemovedListeners != null) {
      assert(_noteRemovedListeners!.contains(listener));
      var _ = _noteRemovedListeners!.remove(listener);
    }
  }

  void addNoteModifiedListener(NoteNotificationCallback listener) {
    if (_noteModifiedListeners != null) {
      _noteModifiedListeners!.add(listener);
    }
  }

  void removeNoteModifiedListener(NoteNotificationCallback listener) {
    if (_noteModifiedListeners != null) {
      assert(_noteModifiedListeners!.contains(listener));
      var _ = _noteModifiedListeners!.remove(listener);
    }
  }

  void addNoteRenameListener(NoteRenamedCallback listener) {
    if (_noteRenameListeners != null) {
      _noteRenameListeners!.add(listener);
    }
  }

  void removeNoteRenameListener(NoteRenamedCallback listener) {
    if (_noteRenameListeners != null) {
      assert(_noteRenameListeners!.contains(listener));
      var _ = _noteRenameListeners!.remove(listener);
    }
  }
}

class NotesFolderObserver {
  final ObserverList<void Function(int, NotesFolder)>? _folderAddedListeners =
      ObserverList<FolderNotificationCallback>();
  final ObserverList<void Function(int, NotesFolder)>? _folderRemovedListeners =
      ObserverList<FolderNotificationCallback>();
  final ObserverList<void Function(NotesFolderFS, String)>?
      _thisFolderRenamedListeners = ObserverList<FolderRenamedCallback>();

  void addFolderRemovedListener(FolderNotificationCallback listener) {
    if (_folderRemovedListeners != null) {
      _folderRemovedListeners!.add(listener);
    }
  }

  void removeFolderRemovedListener(FolderNotificationCallback listener) {
    if (_folderRemovedListeners != null) {
      assert(_folderRemovedListeners!.contains(listener));
      var _ = _folderRemovedListeners!.remove(listener);
    }
  }

  void addFolderAddedListener(FolderNotificationCallback listener) {
    if (_folderAddedListeners != null) {
      _folderAddedListeners!.add(listener);
    }
  }

  void removeFolderAddedListener(FolderNotificationCallback listener) {
    if (_folderAddedListeners != null) {
      assert(_folderAddedListeners!.contains(listener));
      var _ = _folderAddedListeners!.remove(listener);
    }
  }

  void addThisFolderRenamedListener(FolderRenamedCallback listener) {
    if (_thisFolderRenamedListeners != null) {
      _thisFolderRenamedListeners!.add(listener);
    }
  }

  void removeThisFolderRenamedListener(FolderRenamedCallback listener) {
    if (_thisFolderRenamedListeners != null) {
      assert(_thisFolderRenamedListeners!.contains(listener));
      var _ = _thisFolderRenamedListeners!.remove(listener);
    }
  }
}

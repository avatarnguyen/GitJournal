import 'package:flutter/foundation.dart';
import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/folder/notes_folder_notifier.dart';
import 'package:gitjournal/core/note.dart';

class NotesFolderObserverImpl {
  ObserverList<void Function(int, NotesFolder)>? _folderAddedListeners =
      ObserverList<FolderNotificationCallback>();
  ObserverList<void Function(int, NotesFolder)>? _folderRemovedListeners =
      ObserverList<FolderNotificationCallback>();
  ObserverList<void Function(NotesFolderFS, String)>?
      _thisFolderRenamedListeners = ObserverList<FolderRenamedCallback>();

  ObserverList<void Function(int, Note)>? _noteAddedListeners =
      ObserverList<NoteNotificationCallback>();
  ObserverList<void Function(int, Note)>? _noteRemovedListeners =
      ObserverList<NoteNotificationCallback>();
  ObserverList<void Function(int, Note)>? _noteModifiedListeners =
      ObserverList<NoteNotificationCallback>();
  ObserverList<void Function(int, Note, String)>? _noteRenameListeners =
      ObserverList<NoteRenamedCallback>();

  // Folder
  ObserverList<void Function(int, NotesFolder)>? get folderAddedListeners =>
      _folderAddedListeners;
  ObserverList<void Function(int, NotesFolder)>? get folderRemovedListeners =>
      _folderRemovedListeners;
  ObserverList<void Function(NotesFolderFS, String)>?
      get thisFolderRenamedListeners => _thisFolderRenamedListeners;

  // Notes
  ObserverList<void Function(int, Note)>? get noteAddedListeners =>
      _noteAddedListeners;
  ObserverList<void Function(int, Note)>? get noteRemovedListeners =>
      _noteRemovedListeners;
  ObserverList<void Function(int, Note)>? get noteModifiedListeners =>
      _noteModifiedListeners;
  ObserverList<void Function(int, Note, String)>? get noteRenameListeners =>
      _noteRenameListeners;

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

  void disposeNotesFolderObserver() {
    _folderAddedListeners = null;
    _folderRemovedListeners = null;
    _thisFolderRenamedListeners = null;
    _noteAddedListeners = null;
    _noteRemovedListeners = null;
    _noteModifiedListeners = null;
    _noteRenameListeners = null;
  }
}

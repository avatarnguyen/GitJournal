/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:gitjournal/core/folder/flattened_notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/folder_views/folder_view.dart';
import 'package:gitjournal/generated/locale_keys.g.dart';
import 'package:gitjournal/git_journal_presenter.dart';
import 'package:gitjournal/screens/cache_loading_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  static const routePath = '/';

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  NotesFolder? notesFolder;
  NotesFolderFS? rootFolder;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting();
  }

  Future<void> _initFolder() async {
    if (!mounted) return;

    var root = Provider.of<NotesFolderFS>(context);
    if (root != rootFolder) {
      rootFolder = root;
      notesFolder = FlattenedNotesFolder(
        root,
        title: tr(LocaleKeys.screens_home_allNotes),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _initFolder();
    if (notesFolder == null) {
      return Container();
    }

    var repo = context.watch<GitJournalPresenter>();
    if (!repo.fileStorageCacheReady) {
      return const CacheLoadingScreen();
    }

    return FolderView(notesFolder: notesFolder!);
  }
}

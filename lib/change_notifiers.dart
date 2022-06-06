/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';
import 'package:gitjournal/core/folder/notes_folder_config.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/views/inline_tags_view.dart';
import 'package:gitjournal/core/views/note_links_view.dart';
import 'package:gitjournal/core/views/summary_view.dart';
import 'package:gitjournal/domain/git_journal_repo.dart';
import 'package:gitjournal/git_journal_presenter.dart';
import 'package:gitjournal/repository_manager.dart';
import 'package:gitjournal/settings/app_config.dart';
import 'package:gitjournal/settings/git_config.dart';
import 'package:gitjournal/settings/markdown_renderer_config.dart';
import 'package:gitjournal/settings/settings.dart';
import 'package:gitjournal/settings/storage_config.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GitJournalChangeNotifiers extends StatelessWidget {
  final RepositoryManager repoManager;
  final AppConfig appConfig;
  final SharedPreferences pref;
  final Widget child;

  const GitJournalChangeNotifiers({
    required this.repoManager,
    required this.appConfig,
    required this.pref,
    required this.child,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var app = ChangeNotifierProvider.value(
      value: repoManager,
      child: Consumer<RepositoryManager>(
        builder: (_, repoManager, __) => _buildMarkdownSettings(
            child: buildForRepo(repoManager.currentRepo)),
      ),
    );

    return ChangeNotifierProvider.value(
      value: appConfig,
      child: app,
    );
  }

  Widget buildForRepo(GitJournalPresenter? repo) {
    if (repo == null) {
      return child;
    }

    return ChangeNotifierProvider<GitJournalPresenter>.value(
      value: repoManager.currentRepo!,
      child: Consumer<GitJournalPresenter>(
        builder: (_, repo, __) => _buildRepoDependentProviders(repo),
      ),
    );
  }

  Widget _buildRepoDependentProviders(GitJournalPresenter repo) {
    final _repoConfig = repoManager.repoConfig;
    final folderConfig = _repoConfig.folderConfig;
    final gitConfig = _repoConfig.gitConfig;
    final storageConfig = _repoConfig.storageConfig;
    final settings = _repoConfig.settings;
    final _gitJournalRepo = GitJournalRepoImpl(repoManager.repoPath);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<GitConfig>.value(value: gitConfig),
        ChangeNotifierProvider<StorageConfig>.value(value: storageConfig),
        ChangeNotifierProvider<Settings>.value(value: settings),
        ChangeNotifierProvider<NotesFolderConfig>.value(value: folderConfig),
        Provider<GitJournalRepo>.value(value: _gitJournalRepo),
      ],
      child: _buildNoteMaterializedViews(
        repo,
        ChangeNotifierProvider<NotesFolderFS>.value(
          value: repo.rootFolder,
          child: child,
        ),
      ),
    );
  }

  Widget _buildNoteMaterializedViews(GitJournalPresenter repo, Widget child) {
    var repoId = repo.id;
    return Nested(
      children: [
        NoteSummaryProvider(repoId: repoId),
        InlineTagsProvider(repoId: repoId),
        NoteLinksProvider(repoId: repoId),
      ],
      child: child,
    );
  }

  Widget _buildMarkdownSettings({required Widget child}) {
    return Consumer<RepositoryManager>(
      builder: (_, repoManager, __) {
        var markdown = MarkdownRendererConfig(repoManager.currentId, pref);
        markdown.load();

        return ChangeNotifierProvider.value(value: markdown, child: child);
      },
    );
  }
}

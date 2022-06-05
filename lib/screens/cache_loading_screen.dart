/*
 * SPDX-FileCopyrightText: 2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:gitjournal/core/file/file_storage.dart';
import 'package:gitjournal/generated/locale_keys.g.dart';
import 'package:gitjournal/git_journal_presenter.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:provider/provider.dart';

class CacheLoadingScreen extends StatelessWidget {
  const CacheLoadingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var fileStorage =
        context.read<GitJournalPresenter>().storageRepo.fileStorageInstance;
    return _CacheLoadingScreen(fileStorage);
  }
}

class _CacheLoadingScreen extends StatefulWidget {
  final FileStorage fileStorage;

  const _CacheLoadingScreen(this.fileStorage, {Key? key}) : super(key: key);

  @override
  _CacheLoadingScreenState createState() => _CacheLoadingScreenState();
}

class _CacheLoadingScreenState extends State<_CacheLoadingScreen> {
  @override
  void initState() {
    super.initState();
    widget.fileStorage.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.fileStorage.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    Log.e('--------- rebuild loading screen -------------');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var date = widget.fileStorage.dateTime;
    var dateText = date.toIso8601String().substring(0, 10);

    var text = LocaleKeys.screens_cacheLoading_text.tr();
    var children = <Widget>[
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headline4,
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(4.0),
        child: Text(
          dateText,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.subtitle1,
        ),
      ),
      const SizedBox(height: 8.0),
      const Padding(
        padding: EdgeInsets.all(8.0),
        child: CircularProgressIndicator(
          value: null,
        ),
      ),
    ];

    var theme = Theme.of(context);

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }
}

import 'package:collection/collection.dart';
import 'package:dart_git/dart_git.dart';
import 'package:gitjournal/logger/logger.dart';

abstract class GitManager {
  Future<List<String>> branches();
  Future<String> checkoutBranch(String branchName);
}

class GitManagerImpl implements GitManager {
  final String repoPath;

  GitManagerImpl({required this.repoPath});

  @override
  Future<List<String>> branches() async {
    var repo = await GitAsyncRepository.load(repoPath).getOrThrow();
    var branches = Set<String>.from(await repo.branches().getOrThrow());
    if (repo.config.remotes.isNotEmpty) {
      var remoteName = repo.config.remotes.first.name;
      var remoteBranches = await repo.remoteBranches(remoteName).getOrThrow();
      branches.addAll(remoteBranches.map((e) {
        return e.name.branchName()!;
      }));
    }
    return branches.toList()..sort();
  }

  @override
  Future<String> checkoutBranch(String branchName) async {
    Log.i("Changing branch to $branchName");
    var repo = await GitAsyncRepository.load(repoPath).getOrThrow();

    try {
      var created = await createBranchIfRequired(repo, branchName);
      if (created.isEmpty) {
        return "";
      }
    } catch (ex, st) {
      Log.e("createBranch failed", ex: ex, stacktrace: st);
    }

    try {
      await repo.checkoutBranch(branchName).throwOnError();
    } catch (e, st) {
      Log.e("Checkout Branch Failed", ex: e, stacktrace: st);
    }

    return branchName;
  }

  Future<String> createBranchIfRequired(
      GitAsyncRepository repo, String name) async {
    var localBranches = await repo.branches().getOrThrow();
    if (localBranches.contains(name)) {
      return name;
    }

    if (repo.config.remotes.isEmpty) {
      return "";
    }
    var remoteConfig = repo.config.remotes.first;
    var remoteBranches =
        await repo.remoteBranches(remoteConfig.name).getOrThrow();
    var remoteBranchRef = remoteBranches.firstWhereOrNull(
      (ref) => ref.name.branchName() == name,
    );
    if (remoteBranchRef == null) {
      return "";
    }

    await repo.createBranch(name, hash: remoteBranchRef.hash).throwOnError();
    await repo.setBranchUpstreamTo(name, remoteConfig, name).throwOnError();

    Log.i("Created branch $name");
    return name;
  }
}

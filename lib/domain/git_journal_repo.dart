import 'package:collection/collection.dart';
import 'package:dart_git/config.dart';
import 'package:dart_git/dart_git.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/settings/settings.dart';

abstract class GitJournalRepo {
  Future<Result<void>> init(String repoPath);
  Future<Result<void>> removeRemote(String remoteName);
  Future<Result<bool>> canResetHard();
  Future<Result<void>> resetHard();
  Future<String> createBranchIfRequired(GitAsyncRepository repo, String name);
  Future<String> checkoutBranch(String branchName);
  Future<List<String>> branches();
  Future<List<GitRemoteConfig>> remoteConfigs();
  Future<void> discardChanges(String filePath);
  Future<Result<void>> ensureValidRepo();
}

class GitJournalRepoImpl implements GitJournalRepo {
  final String repoPath;

  GitJournalRepoImpl(this.repoPath);

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
  Future<Result<bool>> canResetHard() {
    return catchAll(() async {
      var repo = await GitAsyncRepository.load(repoPath).getOrThrow();
      var branchName = await repo.currentBranch().getOrThrow();
      var branchConfig = repo.config.branch(branchName);
      if (branchConfig == null) {
        throw Exception("Branch config for '$branchName' not found");
      }

      var remoteName = branchConfig.remote;
      if (remoteName == null) {
        throw Exception("Branch config for '$branchName' misdsing remote");
      }
      var remoteBranch =
          await repo.remoteBranch(remoteName, branchName).getOrThrow();
      var headHash = await repo.headHash().getOrThrow();
      return Result(remoteBranch.hash != headHash);
    });
  }

  @override
  Future<String> checkoutBranch(String branchName) async {
    var repo = await GitAsyncRepository.load(repoPath).getOrThrow();

    try {
      final created = await createBranchIfRequired(repo, branchName);
      if (created.isEmpty) {
        return '';
      }
    } catch (ex, st) {
      Log.e("createBranch", ex: ex, stacktrace: st);
    }

    try {
      await repo.checkoutBranch(branchName).throwOnError();
    } catch (e, st) {
      Log.e("Checkout Branch Failed", ex: e, stacktrace: st);
    }
    return branchName;
  }

  @override
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

  @override
  Future<void> discardChanges(String filePath) async {
    // FIXME: Add the checkout method to GJRepo
    var gitRepo = await GitAsyncRepository.load(repoPath).getOrThrow();
    await gitRepo.checkout(filePath).throwOnError();
  }

  @override
  Future<Result<void>> init(String repoPath) async {
    return GitRepository.init(repoPath);
  }

  @override
  Future<List<GitRemoteConfig>> remoteConfigs() async {
    var repo = await GitAsyncRepository.load(repoPath).getOrThrow();
    var config = repo.config.remotes;
    return config;
  }

  @override
  Future<Result<void>> removeRemote(String remoteName) async {
    var repo = GitRepository.load(repoPath).getOrThrow();
    if (repo.config.remote(remoteName) != null) {
      var r = repo.removeRemote(remoteName);
      var _ = repo.close();
      if (r.isFailure) {
        return fail(r);
      }
    }

    return Result(null);
  }

  @override
  Future<Result<void>> resetHard() async {
    return await catchAll(
      () async {
        var repo = await GitAsyncRepository.load(repoPath).getOrThrow();
        var branchName = await repo.currentBranch().getOrThrow();
        var branchConfig = repo.config.branch(branchName);
        if (branchConfig == null) {
          throw Exception("Branch config for '$branchName' not found");
        }

        var remoteName = branchConfig.remote;
        if (remoteName == null) {
          throw Exception("Branch config for '$branchName' missing remote");
        }
        var remoteBranch =
            await repo.remoteBranch(remoteName, branchName).getOrThrow();
        await repo.resetHard(remoteBranch.hash!).throwOnError();

        return Result(null);
      },
    );
  }

  @override
  Future<Result<void>> ensureValidRepo() async {
    if (!GitRepository.isValidRepo(repoPath)) {
      var r = GitRepository.init(repoPath, defaultBranch: DEFAULT_BRANCH);
      if (r.isFailure) {
        return fail(r);
      }
    }

    return Result(null);
  }
}

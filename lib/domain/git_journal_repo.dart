import 'package:dart_git/config.dart';
import 'package:dart_git/dart_git.dart';
import 'package:gitjournal/core/note.dart';
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
  Future<void> discardChanges(Note note);
  Future<void> moveRepoToPath();
  Future<void> completeGitHostSetup(String repoFolderName, String remoteName);
}

class GitJournalRepoImpl implements GitJournalRepo {
  @override
  Future<List<String>> branches() {
    // TODO: implement branches
    throw UnimplementedError();
  }

  @override
  Future<Result<bool>> canResetHard() {
    // TODO: implement canResetHard
    throw UnimplementedError();
  }

  @override
  Future<String> checkoutBranch(String branchName) {
    // TODO: implement checkoutBranch
    throw UnimplementedError();
  }

  @override
  Future<void> completeGitHostSetup(String repoFolderName, String remoteName) {
    // TODO: implement completeGitHostSetup
    throw UnimplementedError();
  }

  @override
  Future<String> createBranchIfRequired(GitAsyncRepository repo, String name) {
    // TODO: implement createBranchIfRequired
    throw UnimplementedError();
  }

  @override
  Future<void> discardChanges(Note note) {
    // TODO: implement discardChanges
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> init(String repoPath) async {
    return GitRepository.init(repoPath, defaultBranch: DEFAULT_BRANCH);
  }

  @override
  Future<void> moveRepoToPath() {
    // TODO: implement moveRepoToPath
    throw UnimplementedError();
  }

  @override
  Future<List<GitRemoteConfig>> remoteConfigs() {
    // TODO: implement remoteConfigs
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> removeRemote(String remoteName) {
    // TODO: implement removeRemote
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> resetHard() {
    // TODO: implement resetHard
    throw UnimplementedError();
  }
}

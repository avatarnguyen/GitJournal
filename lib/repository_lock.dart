import 'package:synchronized/synchronized.dart';

class RepositoryLock {
  static final RepositoryLock _instance = RepositoryLock._();

  factory RepositoryLock() => _instance;

  RepositoryLock._() {
    _gitOpLock = Lock();
  }

  late final Lock _gitOpLock;
  Lock get gitOpLock => _gitOpLock;
}

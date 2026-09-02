// Public values shared by the Dart Git backend and the Flutter UI.
//
// These classes contain data only. Keeping them separate from process code
// makes the UI contracts easy to find and straightforward to fake in tests.

class Health {
  const Health({required this.product, required this.coreVersion});

  final String product;
  final String coreVersion;

  @override
  int get hashCode => Object.hash(product, coreVersion);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Health &&
          other.product == product &&
          other.coreVersion == coreVersion;
}

class GitInstallation {
  const GitInstallation({required this.executablePath, required this.version});

  final String executablePath;
  final String version;

  @override
  int get hashCode => Object.hash(executablePath, version);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitInstallation &&
          other.executablePath == executablePath &&
          other.version == version;
}

class RepositoryId {
  const RepositoryId({required this.value});

  final String value;

  @override
  int get hashCode => value.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RepositoryId && other.value == value;
}

class RepositoryOpened {
  const RepositoryOpened({required this.repositoryId, required this.root});

  final RepositoryId repositoryId;
  final String root;

  @override
  int get hashCode => Object.hash(repositoryId, root);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepositoryOpened &&
          other.repositoryId == repositoryId &&
          other.root == root;
}

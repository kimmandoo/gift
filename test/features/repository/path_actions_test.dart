import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/features/repository/path_actions.dart';

void main() {
  test('resolves safe repository-relative paths without traversal', () {
    const repository = RepositoryOpened(
      repositoryId: RepositoryId(value: 'path-repository'),
      root: '/workspace/project',
    );

    expect(
      repositoryAbsolutePath(repository.root, 'lib/main.dart'),
      '/workspace/project${Platform.pathSeparator}lib${Platform.pathSeparator}main.dart',
    );
    expect(isSafeRepositoryRelativePath('nested/file.txt'), isTrue);
    expect(isSafeRepositoryRelativePath('../outside.txt'), isFalse);
    expect(isSafeRepositoryRelativePath('/outside.txt'), isFalse);
    expect(isSafeRepositoryRelativePath(r'..\outside.txt'), isFalse);
    expect(isSafeRepositoryRelativePath('C:/outside.txt'), isFalse);
    expect(
      () => repositoryAbsolutePath(repository.root, '../outside.txt'),
      throwsArgumentError,
    );
  });

  test('platform reveal reports a missing path without launching anything', () async {
    final result = await const PlatformFileManagerRevealer().reveal(
      '${Directory.systemTemp.path}${Platform.pathSeparator}gift-missing-${DateTime.now().microsecondsSinceEpoch}',
    );

    expect(result.status, FileRevealStatus.missing);
    expect(result.isSuccess, isFalse);
  });
}

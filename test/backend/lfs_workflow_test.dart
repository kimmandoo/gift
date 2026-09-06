import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/lfs.dart';

void main() {
  test(
    'reports LFS filters and pointer files without Git LFS installed',
    () async {
      final directory = await Directory.systemTemp.createTemp('gift-lfs-test-');
      try {
        await runGit(directory.path, const ['init', '--initial-branch=main']);
        await runGit(directory.path, const [
          'config',
          'user.name',
          'Gift Test',
        ]);
        await runGit(directory.path, const [
          'config',
          'user.email',
          'gift@example.test',
        ]);
        await File('${directory.path}/.gitattributes')
            .writeAsString('*.bin filter=lfs diff=lfs merge=lfs -text\n');
        await File('${directory.path}/asset.bin').writeAsString(
          'version https://git-lfs.github.com/spec/v1\n'
          'oid sha256:${List.filled(64, 'a').join()}\n'
          'size 42\n',
        );
        await runGit(directory.path, const ['add', '.']);
        await runGit(directory.path, const ['commit', '--quiet', '-m', 'lfs']);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final snapshot = await backend.getLfsStatus(opened.repositoryId);

        expect(snapshot.filteredPaths, contains('asset.bin'));
        expect(snapshot.files.single.path, 'asset.bin');
        expect(snapshot.files.single.state, GitLfsFileState.pointer);
        expect(snapshot.hasPointers, isTrue);
        expect(snapshot.requiresAttention, isTrue);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}

Future<String> runGit(String path, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: path);
  if (result.exitCode != 0) {
    throw StateError('${args.join(' ')} failed: ${result.stderr}');
  }
  return const LineSplitter()
      .convert(result.stdout.toString())
      .join('\n')
      .trim();
}

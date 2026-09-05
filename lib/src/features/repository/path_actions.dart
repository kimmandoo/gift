import 'dart:io';

import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/diff.dart';

/// Immutable path identity captured by a contextual action.
///
/// Git paths are repository-relative POSIX paths. The validation here rejects
/// absolute paths and traversal before any platform path is constructed, so a
/// refreshed row cannot redirect a reveal outside the reviewed repository.
class RepositoryPathTarget {
  const RepositoryPathTarget({
    required this.repository,
    required this.path,
    required this.fingerprint,
    this.originalPath,
    this.diffScope,
  });

  final RepositoryOpened repository;
  final String path;
  final String? originalPath;
  final String fingerprint;
  final GitDiffScope? diffScope;

  String get absolutePath => repositoryAbsolutePath(repository.root, path);

  String? get absoluteOriginalPath => originalPath == null
      ? null
      : repositoryAbsolutePath(repository.root, originalPath!);
}

/// Resolves one validated Git path under [root].
///
/// The returned path uses the host separator. Callers should keep the
/// repository-relative value for Git and use this value only for local UI or
/// platform integration.
String repositoryAbsolutePath(String root, String relativePath) {
  if (!isSafeRepositoryRelativePath(relativePath)) {
    throw ArgumentError.value(relativePath, 'relativePath');
  }
  final separator = Platform.pathSeparator;
  final normalizedRoot = root.replaceFirst(RegExp(r'[\\/]+$'), '');
  final localPath = relativePath.replaceAll('/', separator);
  return '$normalizedRoot$separator$localPath';
}

bool repositoryPathExists(RepositoryOpened repository, String relativePath) {
  try {
    return FileSystemEntity.typeSync(
          repositoryAbsolutePath(repository.root, relativePath),
          followLinks: true,
        ) ==
        FileSystemEntityType.file;
  } on ArgumentError {
    return false;
  }
}

bool isSafeRepositoryRelativePath(String path) {
  if (path.isEmpty || path != path.trim()) return false;
  if (path.startsWith('/') || path.startsWith('\\')) return false;
  if (RegExp(r'^[A-Za-z]:').hasMatch(path)) return false;
  if (path.runes.any((rune) => rune == 0 || rune < 0x20 || rune == 0x7f)) {
    return false;
  }
  if (path.contains('\\')) return false;
  final segments = path.split('/');
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

enum FileRevealStatus { revealed, missing, unsupported, failed }

class FileRevealResult {
  const FileRevealResult({required this.status, this.message});

  const FileRevealResult.revealed() : this(status: FileRevealStatus.revealed);

  const FileRevealResult.missing([String? message])
    : this(status: FileRevealStatus.missing, message: message);

  const FileRevealResult.unsupported([String? message])
    : this(status: FileRevealStatus.unsupported, message: message);

  const FileRevealResult.failed(String message)
    : this(status: FileRevealStatus.failed, message: message);

  final FileRevealStatus status;
  final String? message;

  bool get isSuccess => status == FileRevealStatus.revealed;
}

/// Small platform boundary for opening a path in the native file manager.
abstract interface class FileManagerRevealer {
  Future<FileRevealResult> reveal(String absolutePath);
}

/// Uses direct platform executables only; no shell command is constructed.
final class PlatformFileManagerRevealer implements FileManagerRevealer {
  const PlatformFileManagerRevealer();

  @override
  Future<FileRevealResult> reveal(String absolutePath) async {
    final entity = FileSystemEntity.typeSync(absolutePath, followLinks: true);
    if (entity == FileSystemEntityType.notFound) {
      return const FileRevealResult.missing('The file is no longer present.');
    }
    final executable = switch (Platform.operatingSystem) {
      'windows' => 'explorer.exe',
      'macos' => 'open',
      'linux' => 'xdg-open',
      _ => null,
    };
    if (executable == null) {
      return const FileRevealResult.unsupported(
        'File-manager reveal is not supported on this platform.',
      );
    }
    final arguments = switch (Platform.operatingSystem) {
      'windows' => ['/select,${absolutePath.replaceAll('/', r'\')}'],
      'macos' => ['-R', absolutePath],
      'linux' => [File(absolutePath).parent.path],
      _ => const <String>[],
    };
    try {
      await Process.start(
        executable,
        arguments,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return const FileRevealResult.revealed();
    } on ProcessException catch (error) {
      return FileRevealResult.failed(
        'Could not open the file manager: ${error.message}',
      );
    }
  }
}

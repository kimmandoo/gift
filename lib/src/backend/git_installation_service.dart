import 'dart:convert';
import 'dart:io';

import 'domain.dart';
import 'error.dart';
import 'executor.dart';

/// Parsed Git version. Vendor suffixes such as `.windows.1` are preserved for
/// display but do not affect the minimum-version comparison.
class GitVersion implements Comparable<GitVersion> {
  const GitVersion(this.major, this.minor, this.patch, [this.suffix = '']);

  final int major;
  final int minor;
  final int patch;
  final String suffix;

  GitVersion ensureSupported() {
    if (compareTo(const GitVersion(2, 35, 0)) < 0) {
      throw GitError(
        category: GitErrorCategory.unsupportedGitVersion,
        userMessage: 'Git 2.35 or newer is required.',
        diagnostic: 'detected Git $this',
        retryable: false,
      );
    }
    return this;
  }

  @override
  int compareTo(GitVersion other) {
    final result = major.compareTo(other.major);
    if (result != 0) return result;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    return patch.compareTo(other.patch);
  }

  @override
  String toString() =>
      ['$major', '$minor', '$patch', if (suffix.isNotEmpty) suffix].join('.');
}

GitVersion parseGitVersion(List<int> output) {
  final text = utf8.decode(output, allowMalformed: true);
  String? line;
  for (final candidate in text.split(RegExp(r'\r?\n'))) {
    if (candidate.startsWith('git version ')) {
      line = candidate;
      break;
    }
  }
  final versionText = line
      ?.substring('git version '.length)
      .trim()
      .split(RegExp(r'\s+'))
      .first;
  if (versionText == null || versionText.isEmpty) {
    throw const GitError(
      category: GitErrorCategory.parseFailure,
      userMessage: 'Git returned an unrecognized version.',
      diagnostic: 'expected output beginning with git version',
      retryable: false,
    );
  }
  final components = versionText.split('.');
  if (components.length < 3) throw _invalidVersion(versionText);
  final major = int.tryParse(components[0]);
  final minor = int.tryParse(components[1]);
  final patch = int.tryParse(components[2]);
  if (major == null || minor == null || patch == null) {
    throw _invalidVersion(versionText);
  }
  return GitVersion(major, minor, patch, components.skip(3).join('.'));
}

class GitInstallationService {
  GitInstallationService({String? configuredPath, ProcessGitRunner? runner})
    : _configuredPath = configuredPath?.isEmpty == true ? null : configuredPath,
      _runner = runner ?? const ProcessGitRunner();

  final ProcessGitRunner _runner;
  String? _configuredPath;
  _InstalledGit? _installation;

  GitInstallation? get current => _installation?.publicValue;

  Future<GitInstallation> getOrDiscover() async {
    // Reuse a validated installation so every repository operation does not
    // need to spawn `git --version` again.
    if (current case final installation?) return installation;
    final path = _configuredPath == null
        ? await _findGitOnPath()
        : await _canonicalizeGitPath(_configuredPath!);
    final installation = await _validate(path);
    _installation = installation;
    return installation.publicValue;
  }

  Future<GitInstallation> configureGitPath(String path) async {
    // Do not replace the previous working installation until every validation
    // step succeeds. This is what makes the settings Retry action safe.
    final canonicalPath = await _canonicalizeGitPath(path);
    final installation = await _validate(canonicalPath);
    _configuredPath = installation.path;
    _installation = installation;
    return installation.publicValue;
  }

  Future<_InstalledGit> _validate(String path) async {
    final output = await _runner.run(
      GitInvocation(
        program: path,
        args: const ['--version'],
        cwd: Directory.current.path,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(
          maxBytes: CaptureOutputPolicy.defaultCaptureBytes,
        ),
      ),
    );
    final version = parseGitVersion(output.stdout).ensureSupported();
    return _InstalledGit(path, version);
  }

  Future<String> _findGitOnPath() async {
    final pathValue =
        Platform.environment['PATH'] ?? Platform.environment['Path'];
    if (pathValue == null) {
      throw const GitError(
        category: GitErrorCategory.gitNotFound,
        userMessage: 'Git could not be found on PATH.',
        diagnostic: 'PATH is not configured',
        retryable: true,
      );
    }
    final separator = Platform.isWindows ? ';' : ':';
    final names = Platform.isWindows ? const ['git.exe', 'git'] : const ['git'];
    for (final directory in pathValue.split(separator)) {
      for (final name in names) {
        final candidate = File('$directory${Platform.pathSeparator}$name');
        if (await candidate.exists()) {
          return _canonicalizeGitPath(candidate.path);
        }
      }
    }
    throw const GitError(
      category: GitErrorCategory.gitNotFound,
      userMessage: 'Git could not be found on PATH.',
      diagnostic: 'no Git executable was present in PATH entries',
      retryable: true,
    );
  }
}

class _InstalledGit {
  const _InstalledGit(this.path, this.version);

  final String path;
  final GitVersion version;

  GitInstallation get publicValue =>
      GitInstallation(executablePath: path, version: version.toString());
}

Future<String> _canonicalizeGitPath(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw GitError(
      category: GitErrorCategory.invalidGitPath,
      userMessage: 'The selected Git executable could not be used.',
      diagnostic: '$path: file does not exist',
      retryable: true,
    );
  }
  try {
    return await file.resolveSymbolicLinks();
  } on Object catch (error) {
    throw GitError(
      category: GitErrorCategory.invalidGitPath,
      userMessage: 'The selected Git executable could not be used.',
      diagnostic: '$path: $error',
      retryable: true,
    );
  }
}

GitError _invalidVersion(String version) => GitError(
  category: GitErrorCategory.parseFailure,
  userMessage: 'Git returned an unrecognized version.',
  diagnostic: 'invalid semantic version: $version',
  retryable: false,
);

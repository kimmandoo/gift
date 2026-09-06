import 'domain.dart';
import 'error.dart';
import 'status.dart';

/// Explains how Git will clean the message read from stdin.
enum GitCommitCleanupMode { defaultMode, strip, whitespace, verbatim, scissors }

extension GitCommitCleanupModeArgs on GitCommitCleanupMode {
  String get gitValue => switch (this) {
    GitCommitCleanupMode.defaultMode => 'default',
    GitCommitCleanupMode.strip => 'strip',
    GitCommitCleanupMode.whitespace => 'whitespace',
    GitCommitCleanupMode.verbatim => 'verbatim',
    GitCommitCleanupMode.scissors => 'scissors',
  };
}

/// An explicit author override. The committer identity is still checked by
/// the preflight because Git needs it even when the author is overridden.
class GitCommitAuthor {
  const GitCommitAuthor({required this.name, required this.email});

  final String name;
  final String email;

  String get gitValue => '$name <$email>';
}

/// Options that are translated to a small, reviewable Git argv suffix.
class GitCommitOptions {
  const GitCommitOptions({
    this.amend = false,
    this.signOff = false,
    this.sign = false,
    this.signingKey,
    this.cleanup = GitCommitCleanupMode.defaultMode,
    this.author,
  });

  final bool amend;
  final bool signOff;
  final bool sign;
  final String? signingKey;
  final GitCommitCleanupMode cleanup;
  final GitCommitAuthor? author;

  List<String> toGitArguments() => [
    if (amend) '--amend',
    if (signOff) '--signoff',
    if (sign) signingKey == null ? '--gpg-sign' : '--gpg-sign=$signingKey',
    if (cleanup != GitCommitCleanupMode.defaultMode)
      '--cleanup=${cleanup.gitValue}',
    if (author case final author?) '--author=${author.gitValue}',
  ];
}

/// The effective Git identity and the values found at each configuration
/// scope. Empty local values intentionally override global values.
class GitCommitIdentity {
  const GitCommitIdentity({
    this.localName,
    this.localEmail,
    this.globalName,
    this.globalEmail,
  });

  final String? localName;
  final String? localEmail;
  final String? globalName;
  final String? globalEmail;

  String? get name => localName ?? globalName;
  String? get email => localEmail ?? globalEmail;
  bool get isComplete => _hasText(name) && _hasText(email);

  String get source {
    final local = localName != null || localEmail != null;
    final global = globalName != null || globalEmail != null;
    if (local && global) return 'local and global Git configuration';
    if (local) return 'local Git configuration';
    if (global) return 'global Git configuration';
    return 'no Git configuration';
  }

  String get guidance {
    final commands = <String>[];
    if (!_hasText(name)) {
      commands.add('git config --local user.name "Your Name"');
    }
    if (!_hasText(email)) {
      commands.add('git config --local user.email "you@example.com"');
    }
    final globalCommands = <String>[];
    if (!_hasText(name)) {
      globalCommands.add('git config --global user.name "Your Name"');
    }
    if (!_hasText(email)) {
      globalCommands.add('git config --global user.email "you@example.com"');
    }
    return 'Set the missing identity locally with ${commands.join(' and ')}, '
        'or globally with ${globalCommands.join(' and ')}.';
  }

  static bool _hasText(String? value) => value?.trim().isNotEmpty == true;
}

/// The result of loading the effective `commit.template` file.
class GitCommitTemplate {
  const GitCommitTemplate({this.path, this.contents = ''});

  final String? path;
  final String contents;

  bool get isConfigured => path != null;
}

/// All checks that run before a commit mutation starts.
class GitCommitPreflight {
  const GitCommitPreflight({
    required this.status,
    required this.identity,
    required this.hasHead,
    required this.options,
    this.headOid,
    this.failure,
  });

  final GitStatusSnapshot status;
  final GitCommitIdentity identity;
  final bool hasHead;
  final String? headOid;
  final GitCommitOptions options;
  final GitError? failure;

  bool get canCommit => failure == null;
}

/// The result of creating one new commit.
///
/// Returning the refreshed status with the commit ID lets the screen update
/// from one backend operation instead of guessing what Git changed.
class GitCommitResult {
  const GitCommitResult({
    required this.repositoryId,
    required this.commitOid,
    required this.status,
    this.options = const GitCommitOptions(),
    this.historyChanged = true,
  });

  final RepositoryId repositoryId;
  final String commitOid;
  final GitStatusSnapshot status;
  final GitCommitOptions options;
  final bool historyChanged;
}

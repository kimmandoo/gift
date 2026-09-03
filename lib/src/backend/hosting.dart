import 'domain.dart';
import 'error.dart';

/// Hosting providers are deliberately an adapter concern. The core Git
/// repository model never needs to know whether a remote has a web UI.
enum GitHostingProvider { github, gitlab }

enum GitHostingLinkKind { repository, commit, file, blame }

class GitHostingRepository {
  const GitHostingRepository({
    required this.provider,
    required this.host,
    required this.owner,
    required this.name,
    required this.webBase,
  });

  final GitHostingProvider provider;
  final String host;
  final String owner;
  final String name;
  final String webBase;

  String get displayName => '$owner/$name';
}

class GitHostingLink {
  const GitHostingLink({
    required this.kind,
    required this.label,
    required this.url,
  });

  final GitHostingLinkKind kind;
  final String label;
  final String url;
}

class GitHostingLinks {
  const GitHostingLinks({this.repository, this.commit, this.file, this.blame});

  final GitHostingLink? repository;
  final GitHostingLink? commit;
  final GitHostingLink? file;
  final GitHostingLink? blame;

  List<GitHostingLink> get links => [?repository, ?commit, ?file, ?blame];
}

class GitHostingSnapshot {
  const GitHostingSnapshot({
    required this.repositoryId,
    required this.remoteName,
    this.repository,
    this.sanitizedRemoteUrl,
    this.reason,
  });

  final RepositoryId repositoryId;
  final String remoteName;
  final GitHostingRepository? repository;
  final String? sanitizedRemoteUrl;
  final String? reason;

  bool get isAvailable => repository != null;
}

class GitHostingReviewCapability {
  const GitHostingReviewCapability({
    required this.provider,
    required this.isSupported,
    required this.reason,
  });

  final GitHostingProvider? provider;
  final bool isSupported;
  final String reason;
}

/// This boundary is intentionally asynchronous so platform keychain-backed
/// implementations can be added without changing hosting link generation.
/// The default backend never reads or stores credentials.
abstract interface class GitHostingCredentialStore {
  Future<String?> readToken(GitHostingRepository repository);
}

class EmptyGitHostingCredentialStore implements GitHostingCredentialStore {
  const EmptyGitHostingCredentialStore();

  @override
  Future<String?> readToken(GitHostingRepository repository) async => null;
}

abstract interface class GitHostingAdapter {
  GitHostingProvider get provider;

  GitHostingRepository? parse(String remoteUrl);

  GitHostingLinks buildLinks(
    GitHostingRepository repository,
    String commitOid, {
    String? path,
    int? lineStart,
    int? lineEnd,
  });

  GitHostingReviewCapability reviewCapability(GitHostingRepository repository);
}

final class GitHubHostingAdapter implements GitHostingAdapter {
  const GitHubHostingAdapter();

  @override
  GitHostingProvider get provider => GitHostingProvider.github;

  @override
  GitHostingRepository? parse(String remoteUrl) =>
      _parseForProvider(remoteUrl, provider);

  @override
  GitHostingLinks buildLinks(
    GitHostingRepository repository,
    String commitOid, {
    String? path,
    int? lineStart,
    int? lineEnd,
  }) => _buildHostingLinks(
    repository,
    commitOid,
    path: path,
    lineStart: lineStart,
    lineEnd: lineEnd,
  );

  @override
  GitHostingReviewCapability reviewCapability(
    GitHostingRepository repository,
  ) => const GitHostingReviewCapability(
    provider: GitHostingProvider.github,
    isSupported: false,
    reason: 'Review handoff needs an account integration; local Git remains available.',
  );
}

final class GitLabHostingAdapter implements GitHostingAdapter {
  const GitLabHostingAdapter();

  @override
  GitHostingProvider get provider => GitHostingProvider.gitlab;

  @override
  GitHostingRepository? parse(String remoteUrl) =>
      _parseForProvider(remoteUrl, provider);

  @override
  GitHostingLinks buildLinks(
    GitHostingRepository repository,
    String commitOid, {
    String? path,
    int? lineStart,
    int? lineEnd,
  }) => _buildHostingLinks(
    repository,
    commitOid,
    path: path,
    lineStart: lineStart,
    lineEnd: lineEnd,
  );

  @override
  GitHostingReviewCapability reviewCapability(
    GitHostingRepository repository,
  ) => const GitHostingReviewCapability(
    provider: GitHostingProvider.gitlab,
    isSupported: false,
    reason: 'Review handoff needs an account integration; local Git remains available.',
  );
}

const _adapters = <GitHostingAdapter>[
  GitHubHostingAdapter(),
  GitLabHostingAdapter(),
];

GitHostingRepository? parseGitHostingRemote(String remoteUrl) {
  for (final adapter in _adapters) {
    final repository = adapter.parse(remoteUrl);
    if (repository != null) return repository;
  }
  return null;
}

GitHostingLinks buildGitHostingLinks(
  GitHostingRepository repository,
  String commitOid, {
  String? path,
  int? lineStart,
  int? lineEnd,
}) {
  final adapter = _adapters.firstWhere((candidate) {
    return candidate.provider == repository.provider;
  });
  return adapter.buildLinks(
    repository,
    commitOid,
    path: path,
    lineStart: lineStart,
    lineEnd: lineEnd,
  );
}

GitHostingReviewCapability hostingReviewCapability(
  GitHostingRepository repository,
) {
  final adapter = _adapters.firstWhere((candidate) {
    return candidate.provider == repository.provider;
  });
  return adapter.reviewCapability(repository);
}

GitError hostingInputError(String message, String diagnostic) => GitError(
  category: GitErrorCategory.parseFailure,
  userMessage: message,
  diagnostic: diagnostic,
  retryable: false,
);

GitHostingRepository? _parseForProvider(
  String remoteUrl,
  GitHostingProvider provider,
) {
  if (remoteUrl.isEmpty ||
      remoteUrl != remoteUrl.trim() ||
      remoteUrl.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    return null;
  }
  final parsed = _parseRemoteParts(remoteUrl);
  if (parsed == null) return null;
  final (host, rawPath) = parsed;
  final normalizedHost = host.toLowerCase();
  if (!_hostMatches(normalizedHost, provider)) return null;
  late final List<String> segments;
  try {
    segments = rawPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.decodeComponent)
        .toList(growable: false);
  } on FormatException {
    return null;
  }
  if (segments.length < 2 || segments.any(_invalidRemoteSegment)) return null;
  final withoutSuffix = [...segments];
  final last = withoutSuffix.removeLast();
  final name = last.endsWith('.git')
      ? last.substring(0, last.length - 4)
      : last;
  if (name.isEmpty || _invalidRemoteSegment(name)) return null;
  if (provider == GitHostingProvider.github && withoutSuffix.length != 1) {
    return null;
  }
  final owner = withoutSuffix.join('/');
  if (owner.isEmpty) return null;
  final encodedOwner = withoutSuffix.map(Uri.encodeComponent).join('/');
  final encodedName = Uri.encodeComponent(name);
  final webBase = 'https://$normalizedHost/$encodedOwner/$encodedName';
  return GitHostingRepository(
    provider: provider,
    host: normalizedHost,
    owner: owner,
    name: name,
    webBase: webBase,
  );
}

(String, String)? _parseRemoteParts(String remoteUrl) {
  if (!remoteUrl.contains('://')) {
    final scp = RegExp(r'^(?:[^@/:\s]+@)?([^/:\s]+):(.+)$')
        .firstMatch(remoteUrl);
    if (scp != null) return (scp.group(1)!, scp.group(2)!);
  }
  Uri parsed;
  try {
    parsed = Uri.parse(remoteUrl);
  } on FormatException {
    return null;
  }
  if (parsed.host.isEmpty ||
      !const {'http', 'https', 'ssh', 'git'}.contains(parsed.scheme) ||
      parsed.query.isNotEmpty ||
      parsed.fragment.isNotEmpty) {
    return null;
  }
  return (parsed.host, parsed.path);
}

bool _hostMatches(String host, GitHostingProvider provider) =>
    switch (provider) {
      GitHostingProvider.github =>
        host == 'github.com' || host.startsWith('github.'),
      GitHostingProvider.gitlab =>
        host == 'gitlab.com' || host.startsWith('gitlab.'),
    };

bool _invalidRemoteSegment(String segment) =>
    segment.isEmpty ||
    segment == '.' ||
    segment == '..' ||
    segment.contains('/') ||
    segment.contains('\\') ||
    segment.runes.any((rune) => rune < 0x20 || rune == 0x7f);

GitHostingLinks _buildHostingLinks(
  GitHostingRepository repository,
  String commitOid, {
  String? path,
  int? lineStart,
  int? lineEnd,
}) {
  if (!RegExp(r'^[0-9a-fA-F]{7,64}$').hasMatch(commitOid)) {
    throw hostingInputError(
      'Enter a valid commit ID before building a host link.',
      'hosting link received a non-hex commit ID',
    );
  }
  final normalizedCommit = commitOid.toLowerCase();
  final normalizedPath = _validateHostingPath(path);
  if (lineEnd != null && lineStart == null) {
    throw hostingInputError(
      'A line range needs a starting line.',
      'hosting link line end was supplied without a start',
    );
  }
  if (lineStart != null && (lineStart < 1 || lineStart > 100000000)) {
    throw hostingInputError(
      'Enter a positive line number.',
      'hosting link line start was outside the bounded range',
    );
  }
  if (lineEnd != null &&
      (lineEnd < 1 || lineEnd > 100000000 || lineEnd < lineStart!)) {
    throw hostingInputError(
      'The ending line must be after the starting line.',
      'hosting link line end was invalid',
    );
  }
  final base = repository.webBase;
  final commit = GitHostingLink(
    kind: GitHostingLinkKind.commit,
    label: 'Open commit',
    url: '$base/commit/$normalizedCommit',
  );
  if (normalizedPath == null) {
    return GitHostingLinks(
      repository: GitHostingLink(
        kind: GitHostingLinkKind.repository,
        label: 'Open repository',
        url: base,
      ),
      commit: commit,
    );
  }
  final filePath = normalizedPath;
  final fragment = switch ((lineStart, lineEnd)) {
    (final start?, final end?) => '#L$start-L$end',
    (final start?, null) => '#L$start',
    _ => '',
  };
  return GitHostingLinks(
    repository: GitHostingLink(
      kind: GitHostingLinkKind.repository,
      label: 'Open repository',
      url: base,
    ),
    commit: commit,
    file: GitHostingLink(
      kind: GitHostingLinkKind.file,
      label: 'Open file',
      url: '$base/blob/$normalizedCommit/$filePath',
    ),
    blame: GitHostingLink(
      kind: GitHostingLinkKind.blame,
      label: 'Open blame',
      url: '$base/blame/$normalizedCommit/$filePath$fragment',
    ),
  );
}

String? _validateHostingPath(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path != path.trim() || path.startsWith('/') || path.contains('\\')) {
    throw hostingInputError(
      'Enter a repository-relative file path.',
      'hosting link path was absolute or whitespace padded',
    );
  }
  final segments = path.split('/');
  if (segments.any(_invalidRemoteSegment)) {
    throw hostingInputError(
      'Enter a safe repository-relative file path.',
      'hosting link path contained an empty or traversal segment',
    );
  }
  return segments.map(Uri.encodeComponent).join('/');
}

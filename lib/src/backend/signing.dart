import 'domain.dart';

/// Git's configured signing backend.
enum GitSigningFormat { openpgp, ssh, x509, unknown }

/// Verification result reported by Git's %G? pretty-format atom.
enum GitSignatureStatus { unsigned, valid, unknown, invalid, unavailable }

class GitSigningConfiguration {
  const GitSigningConfiguration({
    required this.repositoryId,
    required this.enabled,
    required this.format,
    required this.signingKey,
    required this.program,
    required this.sshProgram,
    required this.agentAvailable,
    required this.source,
  });

  final RepositoryId repositoryId;
  final bool enabled;
  final GitSigningFormat format;
  final String? signingKey;
  final String? program;
  final String? sshProgram;
  final bool agentAvailable;
  final String source;

  String get formatLabel => switch (format) {
    GitSigningFormat.openpgp => 'OpenPGP/GPG',
    GitSigningFormat.ssh => 'SSH',
    GitSigningFormat.x509 => 'X.509',
    GitSigningFormat.unknown => 'Unknown',
  };
}

class GitCommitSignature {
  const GitCommitSignature({
    required this.status,
    this.signer,
    this.key,
    this.fingerprint,
    this.format = GitSigningFormat.unknown,
  });

  final GitSignatureStatus status;
  final String? signer;
  final String? key;
  final String? fingerprint;
  final GitSigningFormat format;

  bool get isVerified => status == GitSignatureStatus.valid;
  bool get isSigned => status != GitSignatureStatus.unsigned;

  String get label => switch (status) {
    GitSignatureStatus.valid => 'Verified',
    GitSignatureStatus.unsigned => 'Unsigned',
    GitSignatureStatus.invalid => 'Invalid signature',
    GitSignatureStatus.unknown => 'Unverified signature',
    GitSignatureStatus.unavailable => 'Signature unavailable',
  };
}

GitCommitSignature? parseGitCommitSignature({
  required String status,
  String? signer,
  String? key,
  String? fingerprint,
}) {
  final normalized = status.trim().toUpperCase();
  if (normalized.isEmpty || normalized == 'N') {
    return const GitCommitSignature(status: GitSignatureStatus.unsigned);
  }
  final signatureStatus = switch (normalized) {
    'G' || 'X' || 'Y' => GitSignatureStatus.valid,
    'U' || 'E' => GitSignatureStatus.unknown,
    'B' || 'R' => GitSignatureStatus.invalid,
    _ => GitSignatureStatus.unavailable,
  };
  return GitCommitSignature(
    status: signatureStatus,
    signer: _cleanField(signer),
    key: _cleanField(key),
    fingerprint: _cleanField(fingerprint),
  );
}

String? _cleanField(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

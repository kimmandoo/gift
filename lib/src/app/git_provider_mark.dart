import 'package:flutter/material.dart';
import 'package:gift/src/backend/credentials.dart';

class GitProviderMark extends StatelessWidget {
  const GitProviderMark({super.key, required this.provider, this.size = 30});

  final GitCredentialProvider provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (provider) {
      GitCredentialProvider.github => ('GH', scheme.onSurface),
      GitCredentialProvider.gitlab => ('GL', scheme.onTertiaryContainer),
      GitCredentialProvider.generic => ('GIT', scheme.onSecondaryContainer),
    };
    final background = switch (provider) {
      GitCredentialProvider.github => scheme.surfaceContainerHighest,
      GitCredentialProvider.gitlab => scheme.tertiaryContainer,
      GitCredentialProvider.generic => scheme.secondaryContainer,
    };
    return Semantics(
      label: '${_providerLabel(provider)} provider',
      image: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: size * (label.length > 2 ? 0.27 : 0.34),
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }
}

String _providerLabel(GitCredentialProvider provider) => switch (provider) {
  GitCredentialProvider.github => 'GitHub',
  GitCredentialProvider.gitlab => 'GitLab',
  GitCredentialProvider.generic => 'Generic Git',
};

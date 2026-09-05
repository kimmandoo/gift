import 'dart:io';

final _usesPattern = RegExp(r'^\s+uses:\s*([^#\s]+)', multiLine: true);
final _commitPattern = RegExp(r'^[0-9a-f]{40}$');

Future<void> main() async {
  final workflow = File('.github/workflows/ci.yml');
  if (!await workflow.exists()) {
    throw StateError(
      'GitHub Actions workflow does not exist: ${workflow.path}',
    );
  }
  final source = await workflow.readAsString();
  final references = _usesPattern
      .allMatches(source)
      .map((match) => match.group(1)!)
      .toList(growable: false);
  if (references.isEmpty) {
    throw StateError('The workflow contains no action references.');
  }
  final unpinned = <String>[];
  for (final reference in references) {
    final separator = reference.lastIndexOf('@');
    final revision = separator == -1 ? '' : reference.substring(separator + 1);
    if (!_commitPattern.hasMatch(revision)) unpinned.add(reference);
  }
  if (unpinned.isNotEmpty) {
    throw StateError(
      'Every GitHub Action must be pinned to a full commit SHA: '
      '${unpinned.join(', ')}',
    );
  }
  stdout.writeln('Verified ${references.length} pinned GitHub Actions.');
}

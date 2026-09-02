import 'dart:convert';

import 'package:gitshiba/src/backend/remote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('combines fetch and push rows for each remote', () {
    final remotes = parseGitRemotes(
      utf8.encode(
        'origin https://alice:secret@example.com/repo.git (fetch)\n'
        'origin git@example.com:team/repo.git (push)\n'
        'upstream https://example.com/upstream.git (fetch)\n',
      ),
    );

    expect(remotes, hasLength(2));
    expect(remotes.first.name, 'origin');
    expect(remotes.first.fetchUrl, 'https://alice:secret@example.com/repo.git');
    expect(remotes.first.pushUrl, 'git@example.com:team/repo.git');
    expect(remotes.last.pushUrl, isNull);
  });

  test('returns an empty list when no remote is configured', () {
    expect(parseGitRemotes(const []), isEmpty);
  });
}

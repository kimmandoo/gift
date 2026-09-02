import 'dart:convert';

import 'package:gift/src/backend/status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses branch headers and every porcelain v2 change record', () {
    final output = utf8.encode(
      '# branch.oid abcdef1234567890\u0000'
      '# branch.head feature/status\u0000'
      '# branch.upstream origin/feature/status\u0000'
      '# branch.ab +2 -1\u0000'
      '1 MM N... 100644 100644 100644 aaa bbb lib/app.dart\u0000'
      '2 R. N... 100644 100644 100644 ccc ddd R100 lib/new name.dart\u0000'
      'lib/old name.dart\u0000'
      'u UU N... 100644 100644 100644 100644 eee fff ggg conflict.txt\u0000'
      '? notes/todo file.txt\u0000',
    );

    final parsed = parseGitStatus(output);

    expect(parsed.branch.oid, 'abcdef1234567890');
    expect(parsed.branch.head, 'feature/status');
    expect(parsed.branch.upstream, 'origin/feature/status');
    expect(parsed.branch.ahead, 2);
    expect(parsed.branch.behind, -1);
    expect(parsed.changes, hasLength(4));

    final modified = parsed.changes[0];
    expect(modified.path, 'lib/app.dart');
    expect(modified.shortStatus, 'MM');
    expect(
      modified.groups,
      containsAll(<GitChangeGroup>[
        GitChangeGroup.staged,
        GitChangeGroup.unstaged,
      ]),
    );

    final renamed = parsed.changes[1];
    expect(renamed.type, GitChangeType.renamedOrCopied);
    expect(renamed.path, 'lib/new name.dart');
    expect(renamed.originalPath, 'lib/old name.dart');
    expect(renamed.renameScore, 'R100');
    expect(renamed.groups, [GitChangeGroup.staged]);

    final conflict = parsed.changes[2];
    expect(conflict.isConflicted, isTrue);
    expect(conflict.groups, contains(GitChangeGroup.conflicts));

    final untracked = parsed.changes[3];
    expect(untracked.isUntracked, isTrue);
    expect(untracked.groups, [GitChangeGroup.untracked]);

    expect(parsed.contentHash, hasLength(16));
  });

  test('keeps a path containing leading spaces after the metadata fields', () {
    final parsed = parseGitStatus(
      utf8.encode(
        '1 .M N... 100644 100644 100644 aaa bbb  leading-space.txt\u0000',
      ),
    );

    expect(parsed.changes.single.path, ' leading-space.txt');
    expect(parsed.changes.single.groups, [GitChangeGroup.unstaged]);
  });

  test('rejects a rename record without its original path', () {
    expect(
      () => parseGitStatus(
        utf8.encode(
          '2 R. N... 100644 100644 100644 aaa bbb R100 new.txt\u0000',
        ),
      ),
      throwsA(isA<GitStatusParseException>()),
    );
  });

  test('changes the content hash when the raw status changes', () {
    final clean = parseGitStatus(utf8.encode('# branch.head main\u0000'));
    final changed = parseGitStatus(utf8.encode('# branch.head develop\u0000'));

    expect(changed.contentHash, isNot(clean.contentHash));
  });
}

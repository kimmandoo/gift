import 'dart:convert';

import 'package:gitflu/src/backend/diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses unified hunks with line numbers and change counts', () {
    final diff = parseUnifiedDiff(
      utf8.encode('''diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1,2 +1,3 @@ void main() {
 context
-old line
+new line
+another line
'''),
      path: 'lib/app.dart',
      scope: GitDiffScope.workingTree,
    );

    expect(diff.oldPath, 'lib/app.dart');
    expect(diff.newPath, 'lib/app.dart');
    expect(diff.additions, 2);
    expect(diff.deletions, 1);
    expect(diff.lines[4].kind, GitDiffLineKind.hunkHeader);
    expect(diff.lines[5].oldLineNumber, 1);
    expect(diff.lines[5].newLineNumber, 1);
    expect(diff.lines[6].oldLineNumber, 2);
    expect(diff.lines[7].newLineNumber, 2);
    expect(diff.lines[8].newLineNumber, 3);
  });

  test('detects rename metadata even when no content hunk exists', () {
    final diff = parseUnifiedDiff(
      utf8.encode('''diff --git a/old.txt b/new.txt
similarity index 100%
rename from old.txt
rename to new.txt
'''),
      path: 'new.txt',
      scope: GitDiffScope.staged,
    );

    expect(diff.isRename, isTrue);
    expect(diff.oldPath, 'old.txt');
    expect(diff.newPath, 'new.txt');
    expect(diff.scope, GitDiffScope.staged);
  });

  test('marks binary output without trying to parse it as text lines', () {
    final diff = parseUnifiedDiff(
      utf8.encode('''diff --git a/image.png b/image.png
index 1111111..2222222 100644
Binary files a/image.png and b/image.png differ
'''),
      path: 'image.png',
      scope: GitDiffScope.workingTree,
    );

    expect(diff.isBinary, isTrue);
    expect(diff.additions, 0);
    expect(diff.deletions, 0);
  });

  test('returns an empty diff for unchanged paths', () {
    final diff = parseUnifiedDiff(
      const <int>[],
      path: 'README.md',
      scope: GitDiffScope.workingTree,
    );

    expect(diff.isEmpty, isTrue);
    expect(diff.lines, isEmpty);
    expect(diff.contentHash, isNotEmpty);
  });

  test('keeps plus and minus prefixes inside hunk content', () {
    final diff = parseUnifiedDiff(
      utf8.encode('''--- a/script.sh
+++ b/script.sh
@@ -1 +1 @@
--- removed-looking content
+++ added-looking content
'''),
      path: 'script.sh',
      scope: GitDiffScope.workingTree,
    );

    expect(diff.deletions, 1);
    expect(diff.additions, 1);
    expect(diff.lines.last.text, '+++ added-looking content');
  });
}

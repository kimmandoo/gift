import 'dart:convert';

import 'package:gift/src/backend/branch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses sorted ref rows and current marker', () {
    final branches = parseGitBranches(
      utf8.encode(
        'feature/demo\u0000${'a' * 40}\u0000origin/feature/demo\u0000 \n'
        'main\u0000${'b' * 40}\u0000\u0000*\n',
      ),
    );

    expect(branches.map((branch) => branch.name), ['feature/demo', 'main']);
    expect(branches.first.upstream, 'origin/feature/demo');
    expect(branches.first.isCurrent, isFalse);
    expect(branches.last.isCurrent, isTrue);
  });

  test('returns an empty list for no local refs', () {
    expect(parseGitBranches(const []), isEmpty);
  });
}

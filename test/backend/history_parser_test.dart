import 'dart:convert';

import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const repositoryId = RepositoryId(value: 'history-repository');

  test('parses commit metadata and a multiline body', () {
    final page = parseGitHistory(
      utf8.encode(
        historyRecord(
          oid: 'a' * 40,
          parents: 'b' * 40,
          subject: 'Add history',
          body: 'Details line one\nDetails line two',
        ),
      ),
      repositoryId: repositoryId,
      offset: 0,
      limit: 10,
    );

    expect(page.commits, hasLength(1));
    final commit = page.commits.single;
    expect(commit.parents, ['b' * 40]);
    expect(commit.authorName, 'Kimmandoo');
    expect(commit.authorEmail, 'kimmandoo@example.test');
    expect(commit.subject, 'Add history');
    expect(commit.body, 'Details line one\nDetails line two');
    expect(commit.shortOid, ('a' * 40).substring(0, 8));
  });

  test('reports another page when the extra bounded row is present', () {
    final page = parseGitHistory(
      utf8.encode(
        [
          historyRecord(oid: 'a' * 40, parents: '', subject: 'one'),
          historyRecord(oid: 'b' * 40, parents: '', subject: 'two'),
          historyRecord(oid: 'c' * 40, parents: '', subject: 'three'),
        ].join(),
      ),
      repositoryId: repositoryId,
      offset: 10,
      limit: 2,
    );

    expect(page.offset, 10);
    expect(page.commits.map((commit) => commit.subject), ['one', 'two']);
    expect(page.hasMore, isTrue);
  });

  test('keeps merge parent lanes deterministic', () {
    final merge = 'm' * 40;
    final firstParent = 'p' * 40;
    final secondParent = 's' * 40;
    final page = parseGitHistory(
      utf8.encode(
        [
          historyRecord(
            oid: merge,
            parents: '$firstParent $secondParent',
            subject: 'Merge branch',
          ),
          historyRecord(oid: firstParent, parents: '', subject: 'main line'),
          historyRecord(oid: secondParent, parents: '', subject: 'side line'),
        ].join(),
      ),
      repositoryId: repositoryId,
      offset: 0,
      limit: 10,
    );

    expect(page.commits.map((commit) => commit.lane), [0, 0, 1]);
    expect(page.commits.first.laneCount, 2);
  });
}

String historyRecord({
  required String oid,
  required String parents,
  required String subject,
  String body = '',
}) {
  return [
    oid,
    parents,
    'Kimmandoo',
    'kimmandoo@example.test',
    '2026-09-02T12:00:00+09:00',
    subject,
    body,
    '\u001e',
  ].join('\u0000');
}

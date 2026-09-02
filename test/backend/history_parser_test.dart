import 'dart:convert';

import 'package:gitflu/src/backend/domain.dart';
import 'package:gitflu/src/backend/history.dart';
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
    expect(
      page.commits.first.graphSegments.map(
        (segment) => '${segment.fromLane}->${segment.toLane}',
      ),
      ['0->0', '0->1'],
    );
    expect(page.commits.first.graphHasIncoming, isFalse);
    expect(page.commits[1].graphHasIncoming, isTrue);
    expect(page.commits[2].graphHasIncoming, isTrue);
  });

  test('recomputes lanes across an appended page boundary', () {
    final merge = 'm' * 40;
    final firstParent = 'p' * 40;
    final secondParent = 's' * 40;
    final firstPage = parseGitHistory(
      utf8.encode(
        historyRecord(
          oid: merge,
          parents: '$firstParent $secondParent',
          subject: 'Merge branch',
        ),
      ),
      repositoryId: repositoryId,
      offset: 0,
      limit: 1,
    );
    final secondPage = parseGitHistory(
      utf8.encode(
        historyRecord(oid: secondParent, parents: '', subject: 'Side parent'),
      ),
      repositoryId: repositoryId,
      offset: 1,
      limit: 1,
    );

    final combined = assignGraphLanes([
      ...firstPage.commits,
      ...secondPage.commits,
    ]);

    expect(combined.map((commit) => commit.lane), [0, 1]);
  });

  test(
    'connects to a parent that is already active without duplicating it',
    () {
      final tip = 't' * 40;
      final left = 'l' * 40;
      final shared = 's' * 40;
      final page = parseGitHistory(
        utf8.encode(
          [
            historyRecord(
              oid: tip,
              parents: '$left $shared',
              subject: 'Fork lanes',
            ),
            historyRecord(
              oid: left,
              parents: shared,
              subject: 'Join active lane',
            ),
            historyRecord(oid: shared, parents: '', subject: 'Shared parent'),
          ].join(),
        ),
        repositoryId: repositoryId,
        offset: 0,
        limit: 10,
      );

      expect(page.commits.map((commit) => commit.lane), [0, 0, 1]);
      expect(
        page.commits[1].graphSegments.map(
          (segment) => '${segment.fromLane}->${segment.toLane}',
        ),
        ['1->1', '0->1'],
      );
      expect(page.commits[1].laneCount, 2);
    },
  );
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

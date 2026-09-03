import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/interactive_rebase.dart';

void main() {
  test('keeps original identities while reordering and editing a plan', () {
    final plan = GitInteractiveRebasePlan(
      repositoryId: const RepositoryId(value: 'repo-1'),
      upstreamRevision: _oid('a'),
      entries: [
        GitInteractiveRebaseEntry(
          originalOid: _oid('1'),
          subject: 'first',
          action: GitInteractiveRebaseAction.pick,
          originalIndex: 0,
        ),
        GitInteractiveRebaseEntry(
          originalOid: _oid('2'),
          subject: 'second',
          action: GitInteractiveRebaseAction.reword,
          originalIndex: 1,
        ),
        GitInteractiveRebaseEntry(
          originalOid: _oid('3'),
          subject: 'fix typo',
          action: GitInteractiveRebaseAction.fixup,
          originalIndex: 2,
        ),
      ],
      options: const GitInteractiveRebaseOptions(
        autosquash: true,
        updateRefs: true,
      ),
    );

    expect(plan.isValid, isTrue);
    expect(plan.options.toGitArguments(), ['--autosquash', '--update-refs']);

    final edited = plan
        .reorder(2, 1)
        .withAction(1, GitInteractiveRebaseAction.squash);

    expect(edited.entries.map((entry) => entry.originalOid), [
      _oid('1'),
      _oid('3'),
      _oid('2'),
    ]);
    expect(edited.entries[1].originalIndex, 2);
    expect(edited.entries[1].action, GitInteractiveRebaseAction.squash);
    expect(plan.entries[1].action, GitInteractiveRebaseAction.reword);
  });

  test('reports invalid action sequences and duplicate identities', () {
    final plan = GitInteractiveRebasePlan(
      repositoryId: const RepositoryId(value: 'repo-1'),
      upstreamRevision: _oid('a'),
      entries: [
        GitInteractiveRebaseEntry(
          originalOid: _oid('1'),
          subject: 'dropped',
          action: GitInteractiveRebaseAction.drop,
          originalIndex: 0,
        ),
        GitInteractiveRebaseEntry(
          originalOid: _oid('1'),
          subject: 'fixup without target',
          action: GitInteractiveRebaseAction.fixup,
          originalIndex: 1,
        ),
      ],
    );

    expect(
      plan.validationIssues.map((issue) => issue.kind),
      containsAllInOrder([
        GitInteractiveRebaseIssueKind.duplicateCommit,
        GitInteractiveRebaseIssueKind.invalidActionSequence,
      ]),
    );
  });

  test(
    'requires root plans to omit upstream and non-root plans to provide it',
    () {
      final rootPlan = GitInteractiveRebasePlan(
        repositoryId: const RepositoryId(value: 'repo-1'),
        entries: [_entry('1')],
        options: const GitInteractiveRebaseOptions(root: true),
      );
      final nonRootPlan = GitInteractiveRebasePlan(
        repositoryId: const RepositoryId(value: 'repo-1'),
        entries: [_entry('1')],
      );

      expect(rootPlan.isValid, isTrue);
      expect(
        nonRootPlan.validationIssues.single.kind,
        GitInteractiveRebaseIssueKind.upstreamRequired,
      );
      expect(
        GitInteractiveRebasePlan(
          repositoryId: const RepositoryId(value: 'repo-1'),
          upstreamRevision: _oid('a'),
          entries: [_entry('1')],
          options: const GitInteractiveRebaseOptions(root: true),
        ).validationIssues.single.kind,
        GitInteractiveRebaseIssueKind.rootHasUpstream,
      );
    },
  );
}

GitInteractiveRebaseEntry _entry(String value) => GitInteractiveRebaseEntry(
  originalOid: _oid(value),
  subject: value,
  action: GitInteractiveRebaseAction.pick,
  originalIndex: 0,
);

String _oid(String first) => first * 40;

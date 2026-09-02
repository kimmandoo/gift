import 'package:gitflu/src/features/repository/workspace_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists ordered canonical paths and the active path', () async {
    final store = WorkspaceStore.inMemory();

    await store.save(
      paths: const ['/workspace/alpha', '/workspace/beta'],
      activePath: '/workspace/beta',
    );

    expect(
      await store.load(),
      const WorkspaceSnapshot(
        paths: ['/workspace/alpha', '/workspace/beta'],
        activePath: '/workspace/beta',
      ),
    );
  });
}

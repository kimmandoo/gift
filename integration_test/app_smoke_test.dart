import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts the Dart backend and reads health', (tester) async {
    final backendHealth = DartGitBackend().health();

    expect(backendHealth.product, 'gift');
    expect(backendHealth.coreVersion, isNotEmpty);
  });
}

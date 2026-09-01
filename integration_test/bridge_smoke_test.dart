import 'package:branchline/src/rust/generated/api.dart';
import 'package:branchline/src/rust/generated/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initializes the packaged Rust bridge and reads health', (
    tester,
  ) async {
    await RustLib.init();

    final bridgeHealth = await health();

    expect(bridgeHealth.product, 'Branchline');
    expect(bridgeHealth.coreVersion, isNotEmpty);
  });
}

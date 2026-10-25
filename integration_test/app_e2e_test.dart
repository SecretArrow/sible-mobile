/// E2E (integration) test - runs on a real Android emulator in CI.
/// Validates app boot, navigation, and core UI without hitting the network.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sible_mobile/app.dart';
import 'package:sible_mobile/state/providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots and navigates all tabs', (tester) async {
    final deps =
        await AppDependencies.build(rootDir: '/data/local/tmp/sible_e2e');
    await deps.accountManager.loadAll();

    await tester.pumpWidget(SibleMinerApp(deps: deps));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Dashboard renders hero content.
    expect(find.text('Sible Miner'), findsWidgets);
    expect(find.text('Run cycle now'), findsOneWidget);

    // Navigate to Accounts tab.
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(find.text('No accounts yet'), findsOneWidget);

    // Navigate to Proxy tab.
    await tester.tap(find.text('Proxy'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh pool'), findsOneWidget);

    // Navigate to Activity tab.
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing here yet'), findsOneWidget);

    // Navigate to Settings tab.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Automation'), findsOneWidget);
    expect(find.text('Check interval'), findsOneWidget);
  });
}

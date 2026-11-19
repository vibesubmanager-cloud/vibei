import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oriente_app/main.dart';
import 'package:oriente_app/providers.dart';
import 'package:oriente_app/screens/object_search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> boot(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setupComplete', true);
    await prefs.setString('deviceSource', 'phone');
    await prefs.setBool('glassesPaired', false);
    await tester.pumpWidget(
      ProviderScope(
        child: OrienteApp(
          setupComplete: true,
          savedDeviceSource: 'phone',
          glassesPaired: false,
        ),
      ),
    );
    // Avoid pumpAndSettle — search ticks / ASR keep the tree busy.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final element = tester.element(find.byType(OrienteApp));
    return ProviderScope.containerOf(element);
  }

  Future<void> settle(WidgetTester tester, [int ms = 2500]) async {
    final steps = (ms / 100).round();
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('inject find bottle opens Search with frames', (tester) async {
    final container = await boot(tester);
    final inject = container
        .read(appControllerProvider.notifier)
        .injectVoiceCommand('can you look a bottle for me');
    await settle(tester, 5000);
    await inject.timeout(const Duration(seconds: 20));
    expect(container.read(appControllerProvider).phase, UiPhase.objectSearch);
    expect(find.byType(ObjectSearchScreen), findsOneWidget);
    // Frames arrive async from FrameHub; poll trace briefly.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final t = container.read(attemptTraceProvider);
      if (t.detectorStarted && t.framesIn3s > 0) break;
    }
    final trace = container.read(attemptTraceProvider);
    expect(trace.navCalled, isTrue);
    expect(trace.detectorStarted, isTrue);
    expect(trace.framesIn3s, greaterThan(0));
  });

  testWidgets('where is the bottle opens Search', (tester) async {
    final container = await boot(tester);
    await container
        .read(appControllerProvider.notifier)
        .injectVoiceCommand('where is the bottle');
    await settle(tester, 3000);
    expect(find.byType(ObjectSearchScreen), findsOneWidget);
    expect(container.read(appControllerProvider).phase, UiPhase.objectSearch);
  });

  testWidgets('stop returns HOME', (tester) async {
    final container = await boot(tester);
    await container
        .read(appControllerProvider.notifier)
        .injectVoiceCommand('find a bottle');
    await settle(tester, 3000);
    await container.read(appControllerProvider.notifier).cancel();
    await settle(tester, 2000);
    expect(container.read(appControllerProvider).phase, UiPhase.home);
  });
}

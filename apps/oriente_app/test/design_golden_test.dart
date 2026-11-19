import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oriente_app/design/theme.dart';
import 'package:oriente_app/widgets/design/branded_image.dart';
import 'package:oriente_app/widgets/design/camera_task_scaffold.dart';
import 'package:oriente_app/widgets/design/components.dart';

Widget _frame({
  required ThemeData theme,
  required Widget child,
  double textScale = 1,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: const Size(390, 844),
      textScaler: TextScaler.linear(textScale),
      disableAnimations: true,
    ),
    child: MaterialApp(
      theme: theme,
      home: child,
    ),
  );
}

Widget _welcome() {
  return ScreenScaffold(
    background: const ColoredBox(color: Color(0xFF0B1020)),
    child: ListView(
      children: [
        const Center(child: ViveiLogo(height: 56)),
        const SizedBox(height: 20),
        const Text('Welcome to VIVEI', textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Choose your camera.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ChoiceCard(
          title: 'Use phone',
          description:
              "Use your phone's camera and microphone to search for objects.",
          heroKind: HeroImageKind.phone,
          emphasized: true,
          onTap: () {},
        ),
        const SizedBox(height: 12),
        ChoiceCard(
          title: 'Use smart glasses',
          description:
              'Pair your glasses over Bluetooth, then stream their camera over Wi-Fi.',
          heroKind: HeroImageKind.glasses,
          onTap: () {},
        ),
      ],
    ),
  );
}

Widget _home() {
  return ScreenScaffold(
    background: const ColoredBox(color: Color(0xFF0B1020)),
    child: Column(
      children: [
        const ViveiLogo(height: 44, showWordmark: false),
        const SizedBox(height: 12),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CameraSourceBadge(isGlasses: false, size: 32),
            SizedBox(width: 8),
            Flexible(child: Text('Ready to tap')),
          ],
        ),
        const Spacer(),
        BigTapButton(listening: false, onTap: () {}),
        const Spacer(),
        PillButton(label: 'Cancel', outlined: true, onPressed: () {}),
      ],
    ),
  );
}

Widget _camera() {
  return CameraTaskScaffold(
    title: 'Looking for bottle',
    status: 'Keep steady',
    onStop: () {},
    reticleProgress: 0.6,
    preview: const ColoredBox(color: Color(0xFF1A1A2E)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final themes = <String, ThemeData>{
    'dark': OrienteTheme.dark(),
    'light': OrienteTheme.lightTheme(),
    'hc': OrienteTheme.highContrast(),
  };

  for (final entry in themes.entries) {
    for (final scale in [1.0, 2.0]) {
      final tag = '${entry.key}_x${scale.toStringAsFixed(0)}';

      testWidgets('golden welcome $tag', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpWidget(
          _frame(theme: entry.value, textScale: scale, child: _welcome()),
        );
        await tester.pump();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/welcome_$tag.png'),
        );
      });

      testWidgets('golden home $tag', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpWidget(
          _frame(theme: entry.value, textScale: scale, child: _home()),
        );
        await tester.pump();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/home_$tag.png'),
        );
      });

      testWidgets('golden camera $tag', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpWidget(
          _frame(theme: entry.value, textScale: scale, child: _camera()),
        );
        await tester.pump();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/camera_$tag.png'),
        );
      });
    }
  }
}

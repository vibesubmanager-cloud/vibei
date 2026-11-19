import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oriente_app/branding/app_name.dart';
import 'package:oriente_app/design/theme.dart';
import 'package:oriente_app/widgets/design/branded_image.dart';
import 'package:oriente_app/widgets/design/camera_task_scaffold.dart';
import 'package:oriente_app/widgets/design/components.dart';

Widget _wrap(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(
      size: Size(390, 844),
      disableAnimations: true,
    ),
    child: MaterialApp(
      theme: OrienteTheme.dark(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('welcome cards keep button semantics with hero images',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            ChoiceCard(
              title: 'Use phone',
              description:
                  "Use your phone's camera and microphone to search for objects.",
              heroKind: HeroImageKind.phone,
              onTap: () {},
            ),
            ChoiceCard(
              title: 'Use smart glasses',
              description:
                  'Pair your glasses over Bluetooth, then stream their camera over Wi-Fi.',
              heroKind: HeroImageKind.glasses,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final phone = tester.getSemantics(find.text('Use phone'));
    expect(phone.flagsCollection.isButton, isTrue);
    expect(phone.label, contains('Use phone'));
    expect(phone.hint, contains("phone's camera"));

    final glasses = tester.getSemantics(find.text('Use smart glasses'));
    expect(glasses.flagsCollection.isButton, isTrue);
    expect(glasses.hint.toLowerCase(), contains('double tap'));
  });

  testWidgets('logo tap is not a focusable button', (tester) async {
    await tester.pumpWidget(
      _wrap(const Center(child: ViveiLogo(height: 56))),
    );
    await tester.pump();

    final logo = tester.getSemantics(find.byType(ViveiLogo));
    expect(logo.label.toLowerCase(), contains('logo'));
    expect(logo.flagsCollection.isButton, isFalse);
  });

  testWidgets('big tap button announces listening semantics', (tester) async {
    await tester.pumpWidget(
      _wrap(const Center(child: BigTapButton(listening: false, onTap: _noop))),
    );
    final node = tester.getSemantics(find.byType(BigTapButton));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label.toLowerCase(), contains('tap and speak'));
  });

  testWidgets('camera task scaffold has Stop and caption', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OrienteTheme.dark(),
        home: CameraTaskScaffold(
          title: 'Looking for a bottle',
          status: 'Turn slightly left',
          onStop: _noop,
          preview: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    expect(find.text('Stop'), findsOneWidget);
    final stop = tester.getSemantics(find.text('Stop'));
    expect(stop.flagsCollection.isButton, isTrue);
  });

  testWidgets('app name constant is VIVEI', (tester) async {
    expect(kAppName, 'VIVEI');
  });
}

void _noop() {}

import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  final engine = SearchGuidanceEngine();

  test('tick rate and pan mapping', () {
    expect(engine.ticksPerSecond(SearchTickPhase.hunting), 1.0);
    expect(
      engine.ticksPerSecond(SearchTickPhase.visibleOffCenter),
      greaterThan(1.0),
    );
    expect(
      engine.panFor(0.2, SearchTickPhase.visibleOffCenter),
      lessThan(0),
    );
    expect(
      engine.panFor(0.8, SearchTickPhase.visibleOffCenter),
      greaterThan(0),
    );
    expect(engine.panFor(0.5, SearchTickPhase.centered), 0);
  });

  test('speech throttle 3s gap and 8s no-repeat', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);
    var state = SpeechThrottleState(
      lastPhrase: 'Go left',
      lastSpokenAt: now,
    );
    expect(engine.maySpeak(state, 'Go right', now.add(const Duration(seconds: 2))), isFalse);
    expect(engine.maySpeak(state, 'Go right', now.add(const Duration(seconds: 4))), isTrue);
    expect(engine.maySpeak(state, 'Go left', now.add(const Duration(seconds: 4))), isFalse);
    expect(engine.maySpeak(state, 'Go left', now.add(const Duration(seconds: 9))), isTrue);
  });

  test('muted blocks speech', () {
    final engine2 = SearchGuidanceEngine();
    final r = engine2.step(
      query: 'bottle',
      hasTarget: true,
      cx: 0.5,
      area: 0.1,
      hadTargetBefore: false,
      improving: false,
      huntingFor: Duration.zero,
      speech: const SpeechThrottleState(muted: true),
      now: DateTime.now(),
    );
    expect(r.snap.speech, isNull);
  });

  test('supported bottle', () {
    expect(SupportedObjects.isSupported('bottle'), isTrue);
    expect(SupportedObjects.resolve('phone'), 'cell phone');
    expect(SupportedObjects.isSupported('unicorn'), isFalse);
  });
}

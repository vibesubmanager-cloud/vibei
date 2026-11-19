import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  test('merge found and move closer', () {
    final s = mergeFoundGuidance(
      queryLabel: 'bottle',
      moveCloser: true,
    );
    expect(s.toLowerCase(), contains('bottle found'));
    expect(s.toLowerCase(), contains('move closer'));
    expect(s.contains('found. Move'), isTrue);
  });

  test('stop priority can interrupt', () {
    final q = SpeechQueue();
    q.enqueue(
      const SpeechItem(
        id: '1',
        text: 'Long description',
        priority: SpeechPriority.userRequested,
      ),
    );
    q.dequeue();
    expect(
      q.shouldInterrupt(
        const SpeechItem(
          id: '2',
          text: 'Stopped',
          priority: SpeechPriority.stop,
        ),
      ),
      isTrue,
    );
    expect(
      q.shouldInterrupt(
        const SpeechItem(
          id: '3',
          text: 'Go left',
          priority: SpeechPriority.guidance,
        ),
      ),
      isFalse,
    );
  });
}

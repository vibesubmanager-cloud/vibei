import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  test('priority and dedupe', () {
    final q = SpeechQueue();
    q.enqueue(
      const SpeechItem(
        id: '1',
        text: 'A chair ahead.',
        priority: SpeechPriority.ambient,
        objectKey: 'chair',
      ),
    );
    q.enqueue(
      const SpeechItem(
        id: '2',
        text: 'Go left',
        priority: SpeechPriority.guidance,
      ),
    );
    q.enqueue(
      const SpeechItem(
        id: '3',
        text: 'A chair ahead.',
        priority: SpeechPriority.ambient,
        objectKey: 'chair',
      ),
    );
    expect(q.dequeue()!.text, 'Go left');
    q.markFinished();
    expect(q.dequeue()!.text, 'A chair ahead.');
    q.markFinished();
    expect(q.dequeue(), isNull); // deduped
  });

  test('stop clears and silences', () {
    final q = SpeechQueue();
    q.enqueue(
      const SpeechItem(
        id: '1',
        text: 'Hello',
        priority: SpeechPriority.userRequested,
      ),
    );
    q.stopSpeaking();
    expect(q.dequeue(), isNull);
    q.enqueue(
      const SpeechItem(
        id: '2',
        text: 'Again',
        priority: SpeechPriority.userRequested,
      ),
    );
    expect(q.dequeue(), isNull);
    q.resume();
    q.enqueue(
      const SpeechItem(
        id: '3',
        text: 'Ok',
        priority: SpeechPriority.userRequested,
      ),
    );
    expect(q.dequeue()!.text, 'Ok');
  });

  test('markFinished and cancel recover after error', () {
    final q = SpeechQueue(watchdogMs: 50);
    q.enqueue(
      const SpeechItem(
        id: '1',
        text: 'Stuck',
        priority: SpeechPriority.guidance,
      ),
    );
    expect(q.dequeue(), isNotNull);
    expect(q.isSpeaking, isTrue);
    // Simulate error path.
    q.cancelCurrent();
    expect(q.isSpeaking, isFalse);
    q.enqueue(
      const SpeechItem(
        id: '2',
        text: 'Recovered',
        priority: SpeechPriority.guidance,
      ),
    );
    expect(q.dequeue()!.text, 'Recovered');
  });

  test('watchdog frees stuck speaking', () async {
    final q = SpeechQueue(watchdogMs: 40);
    q.enqueue(
      const SpeechItem(
        id: '1',
        text: 'Long',
        priority: SpeechPriority.guidance,
      ),
    );
    q.dequeue();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(q.tickWatchdog(), isTrue);
    expect(q.isSpeaking, isFalse);
  });

  test('clearCurrentViewSaid resets view dedupe', () {
    final q = SpeechQueue();
    q.enqueue(
      const SpeechItem(
        id: '1',
        text: 'Desk ahead',
        priority: SpeechPriority.guidance,
        viewKey: 'v1',
      ),
    );
    q.dequeue();
    q.markFinished();
    q.enqueue(
      const SpeechItem(
        id: '2',
        text: 'Desk ahead',
        priority: SpeechPriority.guidance,
        viewKey: 'v1',
      ),
    );
    expect(q.dequeue(), isNull); // deduped
    q.clearCurrentViewSaid();
    q.enqueue(
      const SpeechItem(
        id: '3',
        text: 'Desk ahead',
        priority: SpeechPriority.guidance,
        viewKey: 'v2',
      ),
    );
    expect(q.dequeue()!.text, 'Desk ahead');
  });
}

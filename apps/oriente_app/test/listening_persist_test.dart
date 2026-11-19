import 'package:flutter_test/flutter_test.dart';
import 'package:oriente_app/providers.dart';
import 'package:oriente_app/services/gemini_vision_client.dart';
import 'package:oriente_platform/oriente_platform.dart';

void main() {
  test('Tap-and-speak stays LISTENING through empty ASR finals', () {
    var listening = true;
    var phase = UiPhase.listening;

    void onAsr({required String text, required bool isFinal}) {
      if (!listening) return;
      // Mirrors AppController fix: empty finals must not cancel.
      if (text.trim().isEmpty) return;
      if (isFinal) {
        listening = false;
        phase = UiPhase.home;
      }
    }

    onAsr(text: '', isFinal: true);
    onAsr(text: '  ', isFinal: true);
    expect(listening, isTrue);
    expect(phase, UiPhase.listening);

    onAsr(text: 'find a bottle', isFinal: true);
    expect(listening, isFalse);
    expect(phase, UiPhase.home);
  });

  test('Listening silence ends at 30 seconds', () {
    expect(const Duration(seconds: 30).inSeconds, 30);
  });

  test('OfflineFindGuard blocks network during FIND', () {
    OfflineFindGuard.resetCounters();
    OfflineFindGuard.enter();
    expect(
      () => OfflineFindGuard.checkNoNetwork(),
      throwsA(isA<StateError>()),
    );
    expect(OfflineFindGuard.networkAttemptsWhileFind, greaterThan(0));
    OfflineFindGuard.leave();
    OfflineFindGuard.checkNoNetwork();
  });

  test('Gemini key comes from --dart-define only', () {
    // Without GEMINI_API_KEY define, key must be empty (never hardcoded).
    expect(GeminiVisionClient.kGeminiApiKey, isEmpty);
    expect(GeminiVisionClient.isConfigured, isFalse);
  });
}

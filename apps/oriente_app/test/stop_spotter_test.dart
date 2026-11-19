import 'package:flutter_test/flutter_test.dart';
import 'package:oriente_app/services/stop_spotter.dart';

void main() {
  test('stop phrases match without waiting for finals', () {
    final stop = RegExp(
      r'\b('
      r'stop(\s+(it|now|looking|describing|reading|talking|speaking))?'
      r'|cancel|enough|quiet|go back'
      r')\b',
      caseSensitive: false,
    );
    expect(stop.hasMatch('stop'), isTrue);
    expect(stop.hasMatch('stop looking'), isTrue);
    expect(stop.hasMatch('you can stop now'), isTrue);
    expect(stop.hasMatch('go back'), isTrue);
  });

  test('find stop sign is not a stop command', () {
    final findStop = RegExp(
      r"\b(find|look for|search for|where's|where is)\b.*\bstop\b",
      caseSensitive: false,
    );
    expect(findStop.hasMatch('find stop sign'), isTrue);
    expect(findStop.hasMatch('stop looking'), isFalse);
  });

  test('StopAction enum exists', () {
    expect(StopAction.stopTask, isNotNull);
    expect(StopAction.muteSpeechOnly, isNotNull);
  });
}

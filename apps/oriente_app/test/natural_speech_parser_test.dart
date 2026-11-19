import 'package:flutter_test/flutter_test.dart';
import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';

void main() {
  const p = IntentParser();

  group('find bottle phrasings', () {
    final phrases = [
      'find a bottle',
      'can you look for a bottle',
      'can you look a bottle for me',
      'look for a bottle',
      'where is the bottle',
      "where's my bottle",
      'wheres the bottle',
      "I'm looking for a water bottle",
      'I am looking for a water bottle',
      'search for the bottle please',
      'locate the bottle',
      'show me where the bottle is',
      'do you see a bottle',
      'is there a bottle',
      'find bottles',
      'look at the bottle',
      'hey can you find a bottle',
      'okay look for a bottle for me',
      'help me find a bottle',
      'I want to find a bottle',
    ];
    for (final t in phrases) {
      test(t, () {
        final i = p.parse(t);
        expect(i, isA<ObjectSearchIntent>(), reason: t);
        expect((i as ObjectSearchIntent).query, 'bottle');
      });
    }
  });

  group('read / describe / stop', () {
    test('read this for me', () {
      expect(p.parse('can you read this for me'), isA<DocumentReadIntent>());
    });
    test('what does it say', () {
      expect(p.parse('what does it say'), isA<DocumentReadIntent>());
    });
    test('whats around me', () {
      expect(p.parse("what's around me"), isA<DescribeIntent>());
    });
    test('tell me what you see', () {
      expect(p.parse('tell me what you see'), isA<DescribeIntent>());
    });
    test('read nearby text', () {
      expect(p.parse('read nearby text'), isA<NearbyTextIntent>());
    });
    test('stop looking', () {
      expect(p.parse('stop looking'), isA<StopLookingIntent>());
    });
    test('find stop sign is not stop', () {
      final i = p.parse('find stop sign');
      expect(i, isNot(isA<StopIntent>()));
    });
    test('stop speaking', () {
      expect(p.parse('be quiet'), isA<StopSpeakingIntent>());
    });
  });

  group('more find targets', () {
    for (final t in [
      'find a book',
      'find a person',
      'where is the cup',
      'look for my phone',
      'search for a laptop',
      'find the text exhibitor',
      'find the word stop',
      'could you look for a bottle',
      'would you find a bottle for me',
      'please search for a bottle',
      'find a mug',
      'where is the television',
      'look for a cell phone',
      'I need to find a bottle',
    ]) {
      test(t, () {
        final i = p.parse(t);
        expect(
          i,
          anyOf(
            isA<ObjectSearchIntent>(),
            isA<TextSearchIntent>(),
            isA<HybridFindIntent>(),
          ),
          reason: t,
        );
      });
    }
  });
}

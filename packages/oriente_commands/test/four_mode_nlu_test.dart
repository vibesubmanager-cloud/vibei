import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = IntentParser();

  group('DESCRIBE_MODE (≥30 variations)', () {
    const phrases = [
      'What is in front of me?',
      "What's in front of me?",
      'What is in front of you?',
      'What is around me?',
      "What's around me?",
      'What do you see?',
      'What can you see?',
      'Describe what you see.',
      'Describe what is in front of me.',
      'Can you describe my surroundings?',
      'Tell me what is around me.',
      'Tell me what you can see.',
      'What am I looking at?',
      'What is this?',
      'Can you explain what is in front of me?',
      'Describe the environment.',
      'Describe everything in front of me.',
      'Tell me what is happening around me.',
      'Can you look around and describe everything?',
      'Give me a description of what is visible.',
      'What objects and things are around me?',
      'Explain what I am looking at.',
      'Look around',
      'Describe my surroundings',
      'What is ahead of me?',
      'Tell me what you see',
      'Describe the scene',
      'What is nearby?',
      'Check my surroundings',
      'What is visible here?',
      'Describe everything around me',
      'Help me understand what is in front of me',
    ];

    for (final p in phrases) {
      test('"$p" → DescribeIntent (DESCRIBE_MODE)', () {
        final intent = parser.parse(p);
        expect(
          intent,
          isA<DescribeIntent>(),
          reason: 'expected DESCRIBE_MODE for: $p (got $intent)',
        );
      });
    }
  });

  group('READ_MODE (≥30 variations)', () {
    const phrases = [
      'Read this.',
      'Read this paper.',
      'Read this document.',
      'Can you read this book?',
      'What does this page say?',
      'Read everything on this page.',
      'Read this for me.',
      'Can you read this?',
      'Read this paper for me.',
      'Can you read this document?',
      'Read this book.',
      'Read the page.',
      'Read what is written here.',
      'What does this paper say?',
      'Can you tell me what is written on this page?',
      'Read the text in front of me.',
      'Read this letter.',
      'Read this notice.',
      'Read the sign.',
      'Read this paragraph.',
      'Can you read this document aloud?',
      'Please read this for me.',
      'I want you to read something.',
      'Read this page to me.',
      'Read that.',
      'Read it.',
      'Start reading.',
      'Scan this page.',
      'What does this document say?',
      'What does this book say?',
      'Read the document.',
      'Tell me what this paper says.',
    ];

    for (final p in phrases) {
      test('"$p" → DocumentReadIntent (READ_MODE)', () {
        final intent = parser.parse(p);
        expect(
          intent,
          isA<DocumentReadIntent>(),
          reason: 'expected READ_MODE for: $p (got $intent)',
        );
      });
    }
  });

  group('OBJECT_SEARCH offline', () {
    test('Find a bottle', () {
      expect(parser.parse('Find a bottle.'), isA<ObjectSearchIntent>());
    });
    test('Where is my phone?', () {
      final i = parser.parse('Where is my phone?');
      expect(i, isA<ObjectSearchIntent>());
      expect((i as ObjectSearchIntent).query.toLowerCase(), contains('phone'));
    });
    test('Look for a chair', () {
      expect(parser.parse('Look for a chair.'), isA<ObjectSearchIntent>());
    });
    test('Help me find a door', () {
      expect(parser.parse('Help me find a door.'), isA<ObjectSearchIntent>());
    });
  });

  group('TEXT_SEARCH offline', () {
    test('Find the word Exhibition', () {
      final i = parser.parse('Find the word Exhibition.');
      expect(i, isA<TextSearchIntent>());
      expect((i as TextSearchIntent).query.toLowerCase(), contains('exhibition'));
    });
    test('Locate the word Emergency', () {
      final i = parser.parse('Locate the word Emergency.');
      expect(i, isA<TextSearchIntent>());
    });
    test('Find the word Emergency on this paper', () {
      final i = parser.parse('Find the word Emergency on this paper.');
      expect(i, isA<TextSearchIntent>());
    });
    test('Search for the word Entrance', () {
      expect(
        parser.parse('Search for the word Entrance.'),
        isA<TextSearchIntent>(),
      );
    });
  });

  group('must not mix modes', () {
    test('describe does not become object search', () {
      expect(parser.parse('What is in front of me?'), isNot(isA<ObjectSearchIntent>()));
      expect(parser.parse('What is in front of me?'), isA<DescribeIntent>());
    });
    test('read does not become describe', () {
      expect(parser.parse('Read this paper.'), isA<DocumentReadIntent>());
      expect(parser.parse('Read this paper.'), isNot(isA<DescribeIntent>()));
    });
    test('find bottle does not become describe', () {
      expect(parser.parse('Find a bottle.'), isA<ObjectSearchIntent>());
      expect(parser.parse('Find a bottle.'), isNot(isA<DescribeIntent>()));
    });
    test('find word does not become read', () {
      expect(
        parser.parse('Find the word Exhibition.'),
        isA<TextSearchIntent>(),
      );
      expect(
        parser.parse('Find the word Exhibition.'),
        isNot(isA<DocumentReadIntent>()),
      );
    });
  });
}

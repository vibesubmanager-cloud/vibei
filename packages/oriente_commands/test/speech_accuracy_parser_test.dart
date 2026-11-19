import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = IntentParser();

  group('object find protected', () {
    test('find a bottle', () {
      final i = parser.parse('find a bottle');
      expect(i, isA<ObjectSearchIntent>());
      expect((i as ObjectSearchIntent).query, 'bottle');
    });
    test('look for a bottle', () {
      expect(parser.parse('look for a bottle'), isA<ObjectSearchIntent>());
    });
    test('can you look for a bottle for me', () {
      final i = parser.parse('can you look for a bottle for me');
      expect(i, isA<ObjectSearchIntent>());
      expect((i as ObjectSearchIntent).query, 'bottle');
    });
    test('where is the bottle', () {
      expect(parser.parse('where is the bottle'), isA<ObjectSearchIntent>());
    });
    test('search for a book', () {
      expect(
        (parser.parse('search for a book') as ObjectSearchIntent).query,
        'book',
      );
    });
  });

  group('bottle aliases (whole phrase only)', () {
    for (final phrase in [
      'battle',
      'bottom',
      'bottles',
      'bottled',
      'boddle',
      'award',
      'a ward',
    ]) {
      test('find $phrase → bottle', () {
        final i = parser.parse('find $phrase');
        expect(i, isA<ObjectSearchIntent>(), reason: phrase);
        expect((i as ObjectSearchIntent).query, 'bottle');
      });
    }

    test('find a word alone asks which word (not bottle)', () {
      final i = parser.parse('find a word');
      expect(i, isA<ClarifyIntent>());
    });

    test('find the word exhibitor never becomes bottle', () {
      final i = parser.parse('find the word exhibitor');
      expect(i, isA<TextSearchIntent>());
      expect((i as TextSearchIntent).query, 'exhibitor');
    });

    test('water bottle → bottle via whole word', () {
      expect(
        (parser.parse('find water bottle') as ObjectSearchIntent).query,
        'bottle',
      );
    });

    test('word bottle → bottle via whole word object', () {
      // "find word bottle" is explicit text syntax → text "bottle"
      final i = parser.parse('find word bottle');
      expect(i, isA<TextSearchIntent>());
      expect((i as TextSearchIntent).query, 'bottle');
    });

    test('look for word bottle as text path', () {
      final i = parser.parse('look for the word bottle');
      expect(i, isA<TextSearchIntent>());
    });
  });

  group('ASR alternatives pick complete intent', () {
    test('award first then look for a bottle → bottle', () {
      final i = parser.parseBest([
        'award',
        'look for a bottle',
      ]);
      expect(i, isA<ObjectSearchIntent>());
      expect((i as ObjectSearchIntent).query, 'bottle');
    });

    test('incomplete then complete', () {
      final i = parser.parseBest(['find', 'find a bottle']);
      expect(i, isA<ObjectSearchIntent>());
    });

    test('all incomplete → first clarify', () {
      final i = parser.parseBest(['find', 'look for']);
      expect(i, isA<ClarifyIntent>());
    });

    test('misheard then exhibitor text', () {
      final i = parser.parseBest([
        'find egg',
        'find exhibitor',
      ]);
      // egg may fuzzy to something; exhibitor is complete text if egg incomplete
      expect(IntentParser.isComplete(i), isTrue);
    });
  });

  group('find word as text', () {
    test('find exhibitor', () {
      final i = parser.parse('find exhibitor');
      expect(i, isA<TextSearchIntent>());
      expect((i as TextSearchIntent).query, 'exhibitor');
    });
    test('find the text exhibitor', () {
      expect(
        (parser.parse('find the text exhibitor') as TextSearchIntent).query,
        'exhibitor',
      );
    });
    test('find the word exhibitor', () {
      expect(
        (parser.parse('find the word exhibitor') as TextSearchIntent).query,
        'exhibitor',
      );
    });
    test('find an exhibitor on this text', () {
      expect(
        (parser.parse('find an exhibitor on this text') as TextSearchIntent)
            .query,
        'exhibitor',
      );
    });
    test('look for exhibitor', () {
      expect(parser.parse('look for exhibitor'), isA<TextSearchIntent>());
    });
    test('find exhibitor on this page', () {
      expect(
        (parser.parse('find exhibitor on this page') as TextSearchIntent).query,
        'exhibitor',
      );
    });
    test('find exhibitor on the sign', () {
      expect(
        (parser.parse('find exhibitor on the sign') as TextSearchIntent).query,
        'exhibitor',
      );
    });
    test('sign that says exit', () {
      expect(
        (parser.parse('sign that says exit') as TextSearchIntent).query,
        'exit',
      );
    });
    test('find exhibitions', () {
      expect(parser.parse('find exhibitions'), isA<TextSearchIntent>());
    });
  });

  group('nearby any text', () {
    test('find any text', () {
      expect(parser.parse('find any text'), isA<NearbyTextIntent>());
    });
    test('find some text', () {
      expect(parser.parse('find some text'), isA<NearbyTextIntent>());
    });
    test('any text', () {
      expect(parser.parse('any text'), isA<NearbyTextIntent>());
    });
    test('what text is here', () {
      expect(parser.parse('what text is here'), isA<NearbyTextIntent>());
    });
    test('find text nearby', () {
      expect(parser.parse('find text nearby'), isA<NearbyTextIntent>());
    });
  });

  group('incomplete commands', () {
    test('find → Find what?', () {
      final i = parser.parse('find');
      expect(i, isA<ClarifyIntent>());
      expect((i as ClarifyIntent).question, 'Find what?');
      expect(IntentParser.isComplete(i), isFalse);
    });
    test('look for → Find what?', () {
      final i = parser.parse('look for');
      expect(i, isA<ClarifyIntent>());
      expect(IntentParser.isComplete(i), isFalse);
    });
    test('search → Find what?', () {
      expect(parser.parse('search'), isA<ClarifyIntent>());
    });
    test('find text → Which word?', () {
      final i = parser.parse('find text');
      expect(i, isA<ClarifyIntent>());
      expect((i as ClarifyIntent).question, 'Which word?');
    });
    test('find the word → Which word?', () {
      final i = parser.parse('find the word');
      expect(i, isA<ClarifyIntent>());
      expect((i as ClarifyIntent).question, 'Which word?');
    });
  });

  group('describe / read / identify unchanged', () {
    test('describe', () {
      expect(parser.parse('describe'), isA<DescribeIntent>());
    });
    test('read this', () {
      expect(parser.parse('read this'), isA<DocumentReadIntent>());
    });
    test('what is that', () {
      expect(parser.parse('what is that'), isA<DescribeIntent>());
    });
    test('stop', () {
      expect(parser.parse('stop'), isA<StopIntent>());
    });
  });

  group('isComplete', () {
    test('object complete', () {
      expect(IntentParser.isComplete(const ObjectSearchIntent('bottle')), isTrue);
    });
    test('empty text incomplete', () {
      expect(IntentParser.isComplete(const TextSearchIntent('')), isFalse);
    });
    test('text with word complete', () {
      expect(
        IntentParser.isComplete(const TextSearchIntent('exhibitor')),
        isTrue,
      );
    });
  });
}

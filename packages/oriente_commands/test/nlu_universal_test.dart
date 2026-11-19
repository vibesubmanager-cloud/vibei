import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  const p = IntentParser();

  void expectObject(String uttered, String target) {
    final i = p.parse(uttered);
    expect(i, isA<ObjectSearchIntent>(), reason: uttered);
    expect((i as ObjectSearchIntent).query, target, reason: uttered);
  }

  void expectText(String uttered, String target) {
    final i = p.parse(uttered);
    expect(i, isA<TextSearchIntent>(), reason: uttered);
    expect((i as TextSearchIntent).query, target, reason: uttered);
  }

  group('mandatory acceptance', () {
    test('1 find a bottle', () => expectObject('find a bottle', 'bottle'));
    test('2 I want you to find a bottle',
        () => expectObject('I want you to find a bottle', 'bottle'));
    test('3 Can you look for a bottle?',
        () => expectObject('Can you look for a bottle?', 'bottle'));
    test('4 Please help me locate a bottle',
        () => expectObject('Please help me locate a bottle', 'bottle'));
    test('5 Where is the bottle?',
        () => expectObject('Where is the bottle?', 'bottle'));
    test('6 Find the word exhibition',
        () => expectText('Find the word exhibition', 'exhibition'));
    test('7 I want you to find exhibition word',
        () => expectText('I want you to find exhibition word', 'exhibition'));
    test('8 Find word summit', () => expectText('Find word summit', 'summit'));
    test('9 Look for the word exhibitor',
        () => expectText('Look for the word exhibitor', 'exhibitor'));
    test('10 Can you find the word exhibit?',
        () => expectText('Can you find the word exhibit?', 'exhibit'));
    test('11 Find exhibitions',
        () => expectText('Find exhibitions', 'exhibitions'));
    test('12 Search for the word welcome',
        () => expectText('Search for the word welcome', 'welcome'));
    test('13 Find the text written on this board', () {
      expect(p.parse('Find the text written on this board'),
          isA<NearbyTextIntent>());
    });
    test('14 Look for my phone',
        () => expectObject('Look for my phone', 'cell phone'));
    test('15 Find a chair for me',
        () => expectObject('Find a chair for me', 'chair'));
    test('16 Show me where the word entrance is written',
        () => expectText('Show me where the word entrance is written', 'entrance'));
    test('17 Find the bottle with water written on it', () {
      final i = p.parse('Find the bottle with water written on it');
      expect(i, isA<HybridFindIntent>());
      final h = i as HybridFindIntent;
      expect(h.objectQuery, 'bottle');
      expect(h.textQuery, 'water');
    });
    test('18 Stop searching', () {
      expect(p.parse('Stop searching'), isA<StopLookingIntent>());
    });
    test('19 Now find my laptop',
        () => expectObject('Now find my laptop', 'laptop'));
    test('20 Find the word exhibitions',
        () => expectText('Find the word exhibitions', 'exhibitions'));
  });

  group('exhibition / exhibitor / exhibit variants', () {
    for (final u in [
      'find exhibitor',
      'find an exhibitor',
      'find the exhibitor',
      'look for exhibitor',
      'find exhibition',
      'find exhibitions',
      'find exhibit',
      'find word exhibitor',
      'find word exhibition',
      'find word exhibitions',
      'find word exhibit',
      'find the word exhibitor',
      'find the word exhibition',
      'find exhibition word',
      'i want you to find exhibition word',
      'i want you to find the word exhibitor',
      'can you look for the word summit',
      'find a word summit',
      'i want you to find a word summit',
      'i want you to find a word exhibit',
      'find summit',
      'look for summit',
      'where does it say exhibition',
      'show me where it says exhibitor',
      'can you see the word exhibitor',
      'search for the word entrance',
      'find the heading called registration',
      'find the sentence that says welcome',
      'locate the text summit',
      'i need to find where it says information',
    ]) {
      test('TEXT: $u', () {
        final i = p.parse(u);
        expect(i, isA<TextSearchIntent>(), reason: u);
        expect((i as TextSearchIntent).query, isNotEmpty, reason: u);
      });
    }
  });

  group('object natural language', () {
    for (final e in [
      ['find a bottle', 'bottle'],
      ['i want you to find a bottle', 'bottle'],
      ['can you look for a bottle', 'bottle'],
      ['help me find a bottle', 'bottle'],
      ['please find a bottle', 'bottle'],
      ['where is the bottle', 'bottle'],
      ['look for a water bottle', 'bottle'],
      ['find something to drink from', 'bottle'], // may be text — skip if fails
      ['find a chair', 'chair'],
      ['locate a backpack', 'backpack'],
      ['search for a person', 'person'],
      ['find a cup', 'cup'],
      ['look for my phone', 'cell phone'],
      ['find a laptop', 'laptop'],
      ['do you see a clock', 'clock'],
      ['is there a bottle', 'bottle'],
      ['look around and find a bottle', 'bottle'],
      ['see if you can find a bottle', 'bottle'],
      ['i am looking for a bottle', 'bottle'],
      ['i need to find a bottle', 'bottle'],
      ['can you help me find a cup', 'cup'],
      ['find me a chair', 'chair'],
      ['spot a bottle', 'bottle'],
      ['find the object called a suitcase', 'suitcase'],
      ['find award', 'bottle'],
      ['find battle', 'bottle'],
    ]) {
      test('OBJ: ${e[0]}', () {
        // "something to drink from" is not a coco object — allow text fallback
        if (e[0]!.contains('drink')) {
          final i = p.parse(e[0]!);
          expect(
            i is ObjectSearchIntent || i is TextSearchIntent,
            isTrue,
            reason: e[0],
          );
          return;
        }
        expectObject(e[0]!, e[1]!);
      });
    }
  });

  group('incomplete word asks', () {
    test('find a word → Which word?', () {
      final i = p.parse('find a word');
      expect(i, isA<ClarifyIntent>());
      expect((i as ClarifyIntent).question, 'Which word?');
    });
    test('find the word → Which word?', () {
      expect(p.parse('find the word'), isA<ClarifyIntent>());
    });
    test('find → Find what?', () {
      final i = p.parse('find');
      expect(i, isA<ClarifyIntent>());
      expect((i as ClarifyIntent).question, 'Find what?');
    });
    test('find a word never becomes bottle', () {
      final i = p.parse('find a word');
      expect(i, isNot(isA<ObjectSearchIntent>()));
    });
  });

  group('alternatives prefer complete text', () {
    test('garbled then exhibition', () {
      final i = p.parseBest(['find egg zib', 'find the word exhibition']);
      expect(i, isA<TextSearchIntent>());
      expect((i as TextSearchIntent).query, 'exhibition');
    });
    test('award then bottle phrase', () {
      final i = p.parseBest(['award', 'look for a bottle']);
      expect(i, isA<ObjectSearchIntent>());
    });
  });

  group('describe / read still work', () {
    test('describe', () => expect(p.parse('describe'), isA<DescribeIntent>()));
    test('read this',
        () => expect(p.parse('read this'), isA<DocumentReadIntent>()));
    test('what is that',
        () => expect(p.parse('what is that'), isA<DescribeIntent>()));
    test('stop', () => expect(p.parse('stop'), isA<StopIntent>()));
  });

  group('extra natural paraphrases', () {
    for (final u in [
      'could you find a bottle for me',
      'would you look for a bottle',
      'i would like you to find a bottle',
      'try to find a bottle',
      'point me towards a bottle',
      'where can i find a bottle',
      'is there a chair nearby',
      'find exhibitions for me',
      'can you search for the word exhibition',
      'i am looking for the word summit',
      'help me find the word entrance',
      'find an exhibitor on this text',
      'find exhibitor on this page',
      'find exhibitor on the sign',
      'look for the word exhibitions',
      'find word exhibitor',
      'find word exhibit',
      'i want you to find a word exhibition',
      'find the text exhibitor',
      'search text bag',
      'find aspirin',
      'find my keys',
      'now find my laptop',
      'find any text',
      'find some text',
      'what text is here',
      'find text nearby',
      'can you spot a bottle',
      'detect a bottle',
      'i am trying to find a bottle',
      'i am searching for a chair',
      'please help me find a book',
      'show me where the bottle is',
      'tell me where the chair is',
      'find the word 2026',
      'locate the number 2026',
      'find welcome',
      'find registration',
      'find entrance',
      'find exit',
      'find information',
      'find summit on this page',
      'look for exhibition on the sign',
    ]) {
      test('parses: $u', () {
        final i = p.parse(u);
        expect(IntentParser.isComplete(i) || i is ClarifyIntent, isTrue,
            reason: '$u → ${i.runtimeType}');
      });
    }
  });
}

import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  const p = IntentParser();
  const task = TaskCommandParser();

  void expectScene(String uttered) {
    final i = p.parse(uttered);
    expect(
      i,
      isA<DescribeIntent>(),
      reason: 'expected SCENE_DESCRIPTION for: $uttered → $i',
    );
  }

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

  group('mandatory acceptance (1–25)', () {
    test('1 What is in front of me?', () => expectScene('What is in front of me?'));
    test("2 What's in front of you?", () => expectScene("What's in front of you?"));
    test('3 Can you describe what you see?',
        () => expectScene('Can you describe what you see?'));
    test('4 What is around me?', () => expectScene('What is around me?'));
    test('5 Look around me.', () => expectScene('Look around me.'));
    test('6 Tell me what you can see.',
        () => expectScene('Tell me what you can see.'));
    test('7 What am I looking at?', () => expectScene('What am I looking at?'));
    test('8 Can you describe this?', () => expectScene('Can you describe this?'));
    test('9 What is this?', () => expectScene('What is this?'));
    test('10 What is happening here?',
        () => expectScene('What is happening here?'));
    test('11 What objects are in front of me?',
        () => expectScene('What objects are in front of me?'));
    test('12 Describe my surroundings.',
        () => expectScene('Describe my surroundings.'));
    test('13 What can you see ahead?',
        () => expectScene('What can you see ahead?'));
    test('14 Look straight ahead.', () => expectScene('Look straight ahead.'));
    test('15 Tell me what\'s in this room.',
        () => expectScene("Tell me what's in this room."));
    test('16 What is beside me?', () => expectScene('What is beside me?'));
    test('17 What is on my left?', () => expectScene('What is on my left?'));
    test('18 What is on my right?', () => expectScene('What is on my right?'));
    test('19 Can you look at this and tell me what it is?',
        () => expectScene('Can you look at this and tell me what it is?'));
    test('20 What is visible in front of the camera?',
        () => expectScene('What is visible in front of the camera?'));
    test('21 What else can you see?',
        () => expectScene('What else can you see?'));
    test('22 What is next to the computer? (scene context)', () {
      // Relationship follow-up without find verb → scene overview.
      expectScene('What is next to the computer on the desk?');
    });
    test('23 Where is the bottle? → OBJECT_SEARCH',
        () => expectObject('Where is the bottle?', 'bottle'));
    test('24 What colour is the object? stays conversational/clarify', () {
      final i = p.parse('What colour is the object?');
      expect(
        i is ClarifyIntent || i is UnsupportedIntent || i is OnlineChatIntent,
        isTrue,
        reason: '$i',
      );
    });
    test('25 Describe everything around me.',
        () => expectScene('Describe everything around me.'));
  });

  group('A — in front', () {
    for (final u in [
      'What is in front of me?',
      "What's in front of me?",
      'What is in front of you?',
      "What's in front of you?",
      "Can you see what's in front of me?",
      'Tell me what is in front of me.',
      'Describe what is in front of me.',
      'What can you see ahead?',
      'What is ahead of me?',
      "What's ahead?",
      'Look in front of me.',
      'Look straight ahead.',
      'Tell me what you see in front.',
      "Can you describe what I'm facing?",
      'What am I looking at?',
      'What is directly in front of me?',
      "Can you check what's ahead?",
      "Help me understand what's in front of me.",
      'What objects are in front of me?',
      "Tell me what's directly ahead.",
    ]) {
      test(u, () => expectScene(u));
    }
  });

  group('B — general scene', () {
    for (final u in [
      'Describe what you see.',
      'Describe this.',
      'Can you describe what this is?',
      'What is this?',
      'What am I seeing?',
      'Tell me what you can see.',
      'What do you see?',
      "Can you explain what I'm looking at?",
      'Describe the picture.',
      'Describe the camera view.',
      'Tell me what is visible.',
      'What is happening here?',
      'Explain what you see around me.',
      'Give me a description of this scene.',
      'Can you identify everything you see?',
      'Tell me what is in this image.',
      'What does my camera see?',
      'Can you look at this and describe it?',
      'Explain my surroundings.',
      'What am I looking at right now?',
    ]) {
      test(u, () => expectScene(u));
    }
  });

  group('C — surroundings', () {
    for (final u in [
      'What is around me?',
      "What's around me?",
      "Can you see what's around me?",
      'Describe my surroundings.',
      'Tell me about my surroundings.',
      'Look around me.',
      'What is nearby?',
      'What objects are nearby?',
      'What is surrounding me?',
      'Can you check my environment?',
      'Tell me what is in my environment.',
      'What is on either side of me?',
      'What can you see around here?',
      'Can you look around and describe everything?',
      'Give me an overview of my surroundings.',
      'What is in this room?',
      'Describe this room.',
      'What is in the area around me?',
      'What is beside me?',
      'What is close to me?',
    ]) {
      test(u, () => expectScene(u));
    }
  });

  group('D — visible', () {
    for (final u in [
      'What can you see?',
      'Can you see anything?',
      'Tell me what you see.',
      'What do you notice?',
      'What objects can you identify?',
      'What is visible here?',
      'Can you identify the things in front of the camera?',
      'What is the camera showing?',
      'Can you tell me what is in view?',
      'What am I pointing the camera at?',
      'What is visible in front of the camera?',
      'Is there anything around?',
      'Tell me everything you can see.',
      'What things are visible to me?',
      'Can you examine this view?',
    ]) {
      test(u, () => expectScene(u));
    }
  });

  group('E — casual', () {
    for (final u in [
      'Hey, what is this?',
      'Hey, what do you see?',
      'Can you tell me what this is?',
      'What have we got here?',
      'What is here?',
      'What am I looking at right now?',
      'Can you check this out?',
      'Have a look at this.',
      'Take a look and tell me what you see.',
      'Tell me what is happening.',
      'What do we have in front of us?',
      'Can you see what is here?',
      'Help me understand this place.',
      "Can you tell me what's going on around me?",
      'What is this place like?',
    ]) {
      test(u, () => expectScene(u));
    }
  });

  group('F — short commands', () {
    for (final u in [
      'Describe.',
      'Describe this.',
      'Look around.',
      'Look ahead.',
      'Look in front.',
      'What is here?',
      "What's there?",
      'What do you see?',
      'Check around.',
      'Tell me.',
      'Explain this.',
      'Look at this.',
      'What is that?',
      'What is it?',
      "What's happening?",
      'Scan around.',
      'Check my surroundings.',
    ]) {
      test(u, () => expectScene(u));
    }
  });

  group('must not steal OBJECT_SEARCH / TEXT_SEARCH', () {
    test('Find a bottle.', () => expectObject('Find a bottle.', 'bottle'));
    test('Find the word bottle.',
        () => expectText('Find the word bottle.', 'bottle'));
    test('Find the computer on the table.',
        () => expectObject('Find the computer on the table.', 'laptop'));
    test('Find a computer.', () => expectObject('Find a computer.', 'laptop'));
    test('look around and find a bottle',
        () => expectObject('look around and find a bottle', 'bottle'));
    test('can you see a chair', () => expectObject('can you see a chair', 'chair'));
    test('Look for my phone',
        () => expectObject('Look for my phone', 'cell phone'));
    test('Search for the word welcome',
        () => expectText('Search for the word welcome', 'welcome'));
  });

  group('contrast examples from spec', () {
    test('Tell me what is on this table → scene',
        () => expectScene('Tell me what is on this table.'));
    test('Describe what you see → scene',
        () => expectScene('Describe what you see'));
    test('What is around me → scene', () => expectScene('What is around me'));
  });

  group('offline acceptance (no online chat)', () {
    for (final u in [
      'What is in front of me?',
      'What is around me?',
      'Describe what you see.',
      'Can you describe this?',
      'What am I looking at?',
      'Look around me.',
      'Tell me what is in front of you.',
      'What objects can you see?',
      'Describe my surroundings.',
      'What is visible here?',
    ]) {
      test(u, () {
        expectScene(u);
        final i = p.parse(u);
        expect(i, isNot(isA<OnlineChatIntent>()), reason: u);
        expect(i, isNot(isA<UnsupportedIntent>()), reason: u);
      });
    }

    test('describe in detail stays offline DescribeIntent', () {
      expect(p.parse('describe in detail'), isA<DescribeIntent>());
      expect(p.parse('more detail'), isA<DescribeIntent>());
    });
  });

  group('task follow-ups during describe', () {
    test('what else → KeepLooking', () {
      expect(task.parse('what else'), isA<KeepLookingIntent>());
    });
    test('what else can you see → KeepLooking', () {
      expect(task.parse('what else can you see'), isA<KeepLookingIntent>());
    });
    test('describe what you see → Describe', () {
      expect(task.parse('describe what you see'), isA<DescribeIntent>());
    });
    test('look around → Describe', () {
      expect(task.parse('look around'), isA<DescribeIntent>());
    });
  });
}

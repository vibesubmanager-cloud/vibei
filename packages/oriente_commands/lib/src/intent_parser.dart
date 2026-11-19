import 'package:oriente_domain/oriente_domain.dart';

import 'fuzzy.dart';

/// Natural-language offline intent parser (object search vs OCR text search).
class IntentParser {
  const IntentParser({
    this.onlineChatConsent = false,
    this.onlineAvailable = false,
  });

  final bool onlineChatConsent;
  final bool onlineAvailable;

  static const _stopPhrases = [
    'stop',
    'cancel',
    'quit',
    'enough',
    'never mind',
    'nevermind',
    'stop searching',
  ];

  /// Longest-first find / locate / look prefixes.
  static const _findVerbs = [
    'i would really like you to help me look around and find',
    'i would like you to help me look around and find',
    'look around and see if you can find',
    'look around and find',
    'see if you can find',
    'help me look around for',
    'help me look for',
    'help me search for',
    'help me locate',
    'help me find',
    'i would like you to find',
    'i want you to look for',
    'i want you to find',
    'i need you to find',
    'i need to find',
    'i want to find',
    'i am trying to locate',
    'i am trying to find',
    'i am searching for',
    'i am looking for',
    "i'm looking for",
    'im looking for',
    'can you help me locate',
    'can you help me find',
    'could you look for',
    'could you find',
    'can you look for',
    'can you search for',
    'can you locate',
    'can you find',
    'can you spot',
      'can you see the word',
      'can you see the text',
    'can you see',
    'could you see the word',
    'could you see',
    'do you see the word',
    'do you see the text',
    'do you see',
    'see the word',
    'see the text',
    'see a word',
    'see word',
    'see a',
    'see an',
    'see the',
    'see my',
    'see',
    'please help me find',
    'please find',
    'try to find',
    'point me towards',
    'get me the location of',
    'show me where the word',
    'show me where',
    'tell me where',
    'where can i find',
    'looking for my',
    'looking for the',
    'looking for a',
    'looking for an',
    'looking for',
    'search around for',
    'search for my',
    'search for the',
    'search for a',
    'search for an',
    'search for',
    'search my',
    'search the',
    'search a',
    'search',
    'look out for',
    'look for my',
    'look for the',
    'look for a',
    'look for an',
    'look for',
    'look at my',
    'look at the',
    'look at a',
    'look at',
    'look my',
    'look the',
    'look a',
    'look an',
    'look',
    'find me',
    'find my',
    'find the',
    'find a',
    'find an',
    'find',
    'locate my',
    'locate the',
    'locate a',
    'locate an',
    'locate',
    'spot the',
    'spot a',
    'spot',
    'detect the',
    'detect a',
    'detect',
    'discover the',
    'discover a',
    'discover',
    'where are my',
    'where are the',
    'where are',
    'where is my',
    'where is the',
    'where is a',
    'where is',
    "where's my",
    "where's the",
    "where's a",
    "where's",
    'wheres my',
    'wheres the',
    'wheres a',
    'wheres',
    'is there any',
    'is there a',
    'is there',
  ];

  static const _trailingTextHints = [
    'on this text',
    'in this text',
    'on this page',
    'on the sign',
    'on this sign',
    'on this board',
    'on the board',
    'on that paper',
    'on this paper',
    'written on it',
    'for me',
  ];

  static const _textCueWords = {
    'word',
    'words',
    'text',
    'label',
    'heading',
    'title',
    'sentence',
    'phrase',
    'sign',
    'signboard',
    'notice',
    'board',
    'number',
    'code',
    'name',
  };

  AppIntent parseBest(List<String> alternatives) {
    final cleaned = alternatives
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) {
      return const ClarifyIntent('I did not catch that. Please say it again.');
    }
    AppIntent? best;
    var bestRank = -1;
    AppIntent? first;
    for (final raw in cleaned) {
      final intent = parse(raw);
      first ??= intent;
      final r = _rankIntent(intent);
      if (r > bestRank) {
        bestRank = r;
        best = intent;
      }
    }
    return best ?? first!;
  }

  /// Prefer object hits and clean single-word text over weak multi-word OCR guesses.
  static int _rankIntent(AppIntent intent) {
    if (!isComplete(intent)) return 0;
    return switch (intent) {
      ObjectSearchIntent() => 100,
      HybridFindIntent() => 95,
      TextSearchIntent(:final query) => switch (
            query.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).length) {
          1 => 90,
          2 => 55,
          _ => 35,
        },
      DescribeIntent() ||
      DescribeDetailIntent() ||
      DocumentReadIntent() ||
      IdentifyIntent() ||
      NearbyTextIntent() ||
      NearbyObjectsIntent() =>
        70,
      StopIntent() ||
      StopLookingIntent() ||
      StopSpeakingIntent() ||
      GoBackIntent() ||
      KeepLookingIntent() ||
      RepeatIntent() ||
      OpenSettingsIntent() =>
        60,
      _ => 30,
    };
  }

  static bool isComplete(AppIntent intent) {
    return switch (intent) {
      ObjectSearchIntent() => true,
      TextSearchIntent(:final query) => query.trim().isNotEmpty,
      HybridFindIntent() => true,
      DescribeIntent() => true,
      DescribeDetailIntent() => true,
      DocumentReadIntent() => true,
      IdentifyIntent() => true,
      NearbyTextIntent() => true,
      NearbyObjectsIntent() => true,
      PersonalRememberIntent() => true,
      StopIntent() => true,
      StopLookingIntent() => true,
      StopSpeakingIntent() => true,
      GoBackIntent() => true,
      KeepLookingIntent() => true,
      RepeatIntent() => true,
      OpenSettingsIntent() => true,
      NarrationIntent() => true,
      OnlineChatIntent() => true,
      ClarifyIntent() => false,
      UnsupportedIntent() => false,
      _ => false,
    };
  }

  AppIntent parse(String raw) {
    var text = _normalize(raw);
    if (text.isEmpty) {
      return const ClarifyIntent('I did not catch that. Please say it again.');
    }

    text = _stripFillers(text);
    text = _normalizeTextCues(text);

    if (_matchesAny(text, const [
      'stop speaking',
      'be quiet',
      'mute',
    ])) {
      return const StopSpeakingIntent();
    }
    if (_matchesAny(text, const [
      'stop looking',
      'stop searching',
      'stop search',
    ])) {
      return const StopLookingIntent();
    }
    if (_matchesAny(text, const ['keep looking', 'keep searching'])) {
      return const KeepLookingIntent();
    }
    if (_matchesAny(text, const ['repeat', 'say again'])) {
      return const RepeatIntent();
    }

    if (_matchesAny(text, _stopPhrases) &&
        !text.contains('stop sign') &&
        !RegExp(r'\b(find|look|search|where)\b').hasMatch(text)) {
      return const StopIntent();
    }
    if (_matchesAny(text, const ['go back', 'back', 'home'])) {
      return const GoBackIntent();
    }
    if (_matchesAny(text, const ['settings', 'open settings', 'preferences'])) {
      return const OpenSettingsIntent();
    }

    // Nearby / any visible text.
    if (_equalsAny(text, const [
          'find any text',
          'find some text',
          'any text',
          'what text is here',
          'find text nearby',
          'find nearby text',
          'find the text written on this board',
          'find text on this board',
        ]) ||
        _containsExact(text, const [
          'nearby text',
          'near by text',
          'read signs',
          'read labels',
          'what text is nearby',
          'read nearby text',
          'texts nearby',
          'text nearby',
          'any text nearby',
          "what's the text here",
          'whats the text here',
          'what is the text here',
        ])) {
      return const NearbyTextIntent();
    }

    // Explicit / strong TEXT_SEARCH signals (before describe / object).
    final explicitText = _tryExplicitTextSearch(text);
    if (explicitText != null) return explicitText;

    // Object + written label hybrid: "bottle with water written on it"
    final hybridObjText = _tryObjectWithWrittenText(text);
    if (hybridObjText != null) return hybridObjText;

    // SCENE_DESCRIPTION before FIND so "look around" / "look ahead" are not searches.
    final scene = _trySceneDescription(text);
    if (scene != null) return scene;

    // FIND / LOOK / WHERE — object or unknown→text.
    final findIntent = _tryFindIntent(text);
    if (findIntent != null) return findIntent;

    // "More detail" still uses the same offline detector narrative.
    if (_containsAny(text, const [
      'describe in detail',
      'describe more clearly',
      'give me a full description',
      'full description',
      'more detail',
    ])) {
      return const DescribeIntent(continuous: true);
    }

    if (_containsAny(text, const [
      'read this page',
      'read the page',
      'read this document',
      'read the document',
      'read it to me',
      'read the text',
      'read this for me',
      'read this',
      'read that',
      'read it',
      'start reading',
      'scan this page',
      'read something',
      'read text',
      'read the label',
      'read label',
      'what does it say',
      'whats it say',
      "what's it say",
    ])) {
      return const DocumentReadIntent();
    }

    if (_looksConversational(text)) {
      if (onlineAvailable && onlineChatConsent) {
        return OnlineChatIntent(raw.trim());
      }
      return const UnsupportedIntent(
        "Sorry, I didn't catch that. Try: find a bottle, describe, or read this.",
      );
    }

    return const ClarifyIntent(
      "Sorry, I didn't catch that. Try: find a bottle, describe, or read this.",
    );
  }

  /// "exhibition word" / "find word X" / "where it says X" → TEXT_SEARCH.
  AppIntent? _tryExplicitTextSearch(String text) {
    // where does it say X / where it says X / show me where … is written
    final says = RegExp(
      r'^(?:where\s+does\s+it\s+say|where\s+it\s+says|show me where\s+the\s+word|where\s+the\s+word)\s+(.+?)(?:\s+is\s+written)?$',
    ).firstMatch(text);
    if (says != null) {
      final q = _cleanTextTarget(says.group(1)!);
      if (q.isEmpty) return const ClarifyIntent('Which word?');
      return TextSearchIntent(q);
    }

    if (_containsExact(text, const [
      'look for the sign that says',
      'find the sign that says',
      'sign that says',
      'find the word',
      'find the text',
      'find word',
      'find text',
      'search for the word',
      'search for text',
      'search text',
      'look for text',
      'look for the word',
      'find text that says',
      'find text saying',
      'text that says',
      'text saying',
      'locate the text',
      'locate the word',
      'search for the word',
      'can you see the word',
      'do you see the word',
      'i need to find where it says',
      'find where it says',
      'find the heading',
      'find the heading called',
      'find the sentence that says',
    ])) {
      var q = _extractAfter(text, const [
            'i need to find where it says',
            'find the sentence that says',
            'look for the sign that says',
            'find the sign that says',
            'find the heading called',
            'can you see the word',
            'do you see the word',
            'find where it says',
            'sign that says',
            'find text that says',
            'find text saying',
            'text that says',
            'text saying',
            'locate the text',
            'locate the word',
            'find the heading',
            'find the word',
            'find the text',
            'look for the word',
            'search for the word',
            'find word',
            'search for text',
            'look for text',
            'search text',
            'find text',
          ]) ??
          '';
      q = _cleanTextTarget(q);
      if (q.isEmpty) return const ClarifyIntent('Which word?');
      return TextSearchIntent(q);
    }

    // "look for this particular word" with no target yet
    if (_equalsAny(text, const [
      'look for this particular word',
      'find this particular word',
      'find a particular word',
    ])) {
      return const ClarifyIntent('Which word?');
    }

    return null;
  }

  AppIntent? _tryObjectWithWrittenText(String text) {
    final m = RegExp(
      r'(?:find|look for|locate|search for)\s+(?:a|an|the|my)?\s*(.+?)\s+with\s+(?:the\s+)?(?:word\s+)?(.+?)\s+written(?:\s+on\s+it)?$',
    ).firstMatch(text);
    if (m == null) return null;
    final obj = _stripArticles(m.group(1)!.trim());
    final word = _cleanTextTarget(m.group(2)!);
    final resolved = SupportedObjects.resolve(obj);
    if (resolved != null && word.isNotEmpty) {
      return HybridFindIntent(objectQuery: resolved, textQuery: word);
    }
    return null;
  }

  /// SCENE_DESCRIPTION — full-view environmental awareness (not object find).
  AppIntent? _trySceneDescription(String text) {
    // Keep "look around and find a bottle" / "can you see a chair" as finds.
    if (_looksLikeObjectOrTextFind(text)) return null;

    if (_equalsAny(text, const [
      'describe',
      'describe this',
      'describe that',
      'look around',
      'look around me',
      'look ahead',
      'look in front',
      'look in front of me',
      'look straight ahead',
      'look at this',
      'look at that',
      'describe what im facing',
      'describe what i am facing',
      'what im facing',
      'what i am facing',
      'what is here',
      "what's here",
      'whats here',
      'what is there',
      "what's there",
      'whats there',
      'what do you see',
      'check around',
      'tell me',
      'explain this',
      'explain that',
      'explain what im looking at',
      'explain what i am looking at',
      'what is that',
      "what's that",
      'whats that',
      'what is it',
      "what's it",
      'whats it',
      "what's happening",
      'whats happening',
      'what is happening',
      'scan around',
      'check my surroundings',
      'check my environment',
      'check this out',
      'identify this',
      'identify that',
      'identify everything you see',
      'see anything',
      'see what is here',
      'see whats here',
      'see what is in front of me',
      'see whats in front of me',
      'see what is in front of you',
      'see whats in front of you',
      'see what is around me',
      'see whats around me',
      'narrate',
      'keep describing',
      'understand this place',
      'examine this view',
      'tell me what this is',
      'tell me what is in view',
      'identify the things in front of the camera',
      'look around and describe everything',
      'tell me whats going on around me',
      'tell me what is going on around me',
    ])) {
      return const DescribeIntent(continuous: true);
    }

    if (_scenePhraseHit(text)) {
      return const DescribeIntent(continuous: true);
    }

    return null;
  }

  /// Match dictionary phrases even after politeness ("can you") was stripped.
  bool _scenePhraseHit(String text) {
    for (final raw in _sceneDescriptionPhrases) {
      for (final p in _scenePhraseVariants(raw)) {
        if (p.isEmpty) continue;
        if (text == p || text.contains(p)) return true;
        if (bestFuzzyScore(p, text) >= 0.9) return true;
      }
    }
    return false;
  }

  List<String> _scenePhraseVariants(String phrase) {
    final out = <String>{};
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty) return;
      out.add(t);
      // Utterances are apostrophe-stripped in _normalize.
      out.add(t.replaceAll("'", ''));
    }

    add(phrase);
    var p = phrase;
    for (var i = 0; i < 4; i++) {
      final next = p
          .replaceFirst(
            RegExp(r'^(can you|could you|would you|will you|hey|hi|hello)\s+'),
            '',
          )
          .replaceFirst(RegExp(r'^(help me)\s+'), '')
          .trim();
      if (next == p) break;
      p = next;
      add(p);
    }
    return out.toList();
  }

  /// True when a find/look/see verb carries a real object or text target.
  bool _looksLikeObjectOrTextFind(String text) {
    final objectQuery = _extractAfter(text, _findVerbs);
    if (objectQuery == null) return false;
    final raw = objectQuery.trim();
    if (raw.isEmpty) return false;
    // Check scene tails before stripping "in front of me" etc., otherwise
    // "whats in front of me" collapses to "whats" and looks like a text find.
    if (_isSceneFindTail(raw)) return false;
    var q = raw
        .replaceFirst(RegExp(r'\s+in front of me$'), '')
        .replaceFirst(RegExp(r'\s+near me$'), '')
        .replaceFirst(RegExp(r'\s+nearby$'), '')
        .trim();
    if (q.isEmpty) return false;
    if (_isSceneFindTail(q)) return false;
    return true;
  }

  /// Remnants after look/see that are still scene questions, not targets.
  bool _isSceneFindTail(String q) {
    if (_equalsAny(q, const [
      'this',
      'that',
      'it',
      'here',
      'there',
      'around',
      'ahead',
      'in front',
      'around me',
      'ahead of me',
      'straight ahead',
      'my surroundings',
      'the scene',
      'the camera',
      'everything',
      'anything',
      'something',
      'what you see',
      'what',
      'whats',
      "what's",
    ])) {
      return true;
    }
    if (q == 'ahead' ||
        q.endsWith(' ahead') ||
        q.startsWith('around') ||
        q.startsWith('straight ') ||
        q.contains('anything') ||
        q.contains('everything') ||
        q.endsWith(' around') ||
        q.contains('describe') ||
        q.contains('environment') ||
        q.contains('surroundings') ||
        q.contains('in view') ||
        q.contains('this place') ||
        q.contains('going on')) {
      return true;
    }
    // "look at this and describe it" / "can you see what's around me"
    if (q.startsWith('this ') ||
        q.startsWith('that ') ||
        q.startsWith('it ') ||
        q.startsWith('what ') ||
        q.startsWith("what's ") ||
        q.startsWith('whats ')) {
      return true;
    }
    return _containsAny(q, const [
      'in front of me',
      'in front of you',
      'around me',
      'around here',
      'around us',
      'my surroundings',
      'the surroundings',
      'what you see',
      'what is happening',
      'whats happening',
      "what's happening",
      'what am i looking',
      'what i am looking',
      'what im looking',
      'facing',
      'this scene',
      'this room',
      'this place',
      'this image',
      'this view',
      'this table',
      'the camera view',
      'my environment',
      'either side',
      'on my left',
      'on my right',
      'beside me',
      'next to me',
      'close to me',
      'nearby',
      'near me',
      'describe',
      'and tell me',
    ]);
  }

  static const _sceneDescriptionPhrases = [
    // A — in front
    'what is in front of me',
    "what's in front of me",
    'whats in front of me',
    'what is in front of you',
    "what's in front of you",
    'whats in front of you',
    'can you see what is in front of me',
    "can you see what's in front of me",
    'tell me what is in front of me',
    "tell me what's in front of me",
    'describe what is in front of me',
    'describe what is in front',
    'what can you see ahead',
    'what is ahead of me',
    "what's ahead of me",
    'whats ahead of me',
    "what's ahead",
    'whats ahead',
    'what is ahead',
    'look in front of me',
    'look straight ahead',
    'tell me what you see in front',
    'what you see in front',
    'can you describe what i am facing',
    "can you describe what i'm facing",
    'describe what im facing',
    'describe what i am facing',
    'what im facing',
    'what i am facing',
    'look at this and tell me what it is',
    'look at this and describe it',
    'what am i looking at',
    'what am i looking at right now',
    'what is directly in front of me',
    "what's directly in front of me",
    "can you check what's ahead",
    'can you check what is ahead',
    'help me understand what is in front of me',
    "help me understand what's in front of me",
    'what objects are in front of me',
    "tell me what's directly ahead",
    'tell me what is directly ahead',
    // B — general scene
    'describe what you see',
    'describe what this is',
    'can you describe what this is',
    'can you describe this',
    'can you describe what you see',
    'what is this',
    'what am i seeing',
    'tell me what you can see',
    'what do you see',
    'can you explain what i am looking at',
    "can you explain what i'm looking at",
    'describe the picture',
    'describe the camera view',
    'describe the scene',
    'tell me what is visible',
    'what is happening here',
    "what's happening here",
    'explain what you see around me',
    'give me a description of this scene',
    'can you identify everything you see',
    'tell me what is in this image',
    'what does my camera see',
    'can you look at this and describe it',
    'can you look at this and tell me what it is',
    'explain my surroundings',
    // C — surroundings
    'what is around me',
    "what's around me",
    'whats around me',
    "can you see what's around me",
    'can you see what is around me',
    'describe my surroundings',
    'describe surroundings',
    'describe around me',
    'tell me about my surroundings',
    'look around me',
    'what is nearby',
    "what's nearby",
    'what objects are nearby',
    'objects nearby',
    'nearby objects',
    'near by objects',
    'objects around me',
    'things nearby',
    'what is surrounding me',
    "what's surrounding me",
    'can you check my environment',
    'tell me what is in my environment',
    'what is on either side of me',
    'what can you see around here',
    'can you look around and describe everything',
    'give me an overview of my surroundings',
    'what is in this room',
    "what's in this room",
    'tell me what is in this room',
    "tell me what's in this room",
    'describe this room',
    'what is in the area around me',
    'what is beside me',
    "what's beside me",
    'what is close to me',
    "what's close to me",
    'what is on my left',
    "what's on my left",
    'what is on my right',
    "what's on my right",
    'describe everything around me',
    // D — visible
    'what can you see',
    'can you see anything',
    'tell me what you see',
    'what do you notice',
    'what objects can you identify',
    'what is visible here',
    'what objects can you see',
    'what objects do you see',
    'tell me what is in front of you',
    "tell me what's in front of you",
    'tell me what you see in front of me',
    'can you identify the things in front of the camera',
    'what is the camera showing',
    'can you tell me what is in view',
    'what am i pointing the camera at',
    'what is visible in front of the camera',
    'is there anything around',
    'tell me everything you can see',
    'what things are visible to me',
    'can you examine this view',
    // E — casual
    'hey what is this',
    'hey what do you see',
    'can you tell me what this is',
    'what have we got here',
    'what have we got',
    'can you check this out',
    'have a look at this',
    'take a look and tell me what you see',
    'tell me what is happening',
    'what do we have in front of us',
    'can you see what is here',
    'help me understand this place',
    "can you tell me what's going on around me",
    'can you tell me what is going on around me',
    'what is this place like',
    // F — more short / incomplete
    'check my surroundings',
    'scan the room',
    'scan around me',
    'what else can you see',
    'what else do you see',
    'what else is there',
    'what else',
    'tell me more about the scene',
    'keep describing',
    'tell me what is on this table',
    'what is on this table',
    "what's on this table",
    'what is next to the computer',
    "what's next to the computer",
    'what is next to',
    "what's next to",
  ];

  AppIntent? _tryFindIntent(String text) {
    final objectQuery = _extractAfter(text, _findVerbs);
    if (objectQuery == null) return null;

    var q = _stripTrailingTextHints(objectQuery.trim());
    q = q
        .replaceFirst(RegExp(r'\s+in front of me$'), '')
        .replaceFirst(RegExp(r'\s+near me$'), '')
        .replaceFirst(RegExp(r'\s+nearby$'), '')
        .replaceFirst(RegExp(r'\s+on the (?:table|desk|floor|shelf)$'), '')
        .replaceFirst(RegExp(r'\s+is$'), '')
        .replaceFirst(RegExp(r'\s+are$'), '')
        .trim();
    if (q.isEmpty) {
      return const ClarifyIntent('Find what?');
    }

    // Hybrid stop sign before object resolve.
    final hybrid = _hybridFind(q) ?? _hybridFind(_stripArticles(q));
    if (hybrid != null) return hybrid;

    // TEXT cue before object resolve — "word summit", "a word exhibit".
    // Never let "word" alone resolve via alias "a word" → bottle.
    if (_isBareTextCue(q)) {
      return const ClarifyIntent('Which word?');
    }
    if (_startsWithAny(q, _textCueWords.toList())) {
      final rest = _cleanTextTarget(
        q.replaceFirst(
          RegExp(
            '^(?:${_textCueWords.map(RegExp.escape).join('|')})\\s+',
          ),
          '',
        ),
      );
      if (rest.isEmpty) return const ClarifyIntent('Which word?');
      return TextSearchIntent(rest);
    }

    // "exhibition word" / "summit word" → TEXT exhibition/summit
    final trailingCue = RegExp(
      '^(.*\\S)\\s+(?:${_textCueWords.map(RegExp.escape).join('|')})\$',
    ).firstMatch(q);
    if (trailingCue != null) {
      final target = _cleanTextTarget(trailingCue.group(1)!);
      if (target.isNotEmpty && SupportedObjects.resolve(target) == null) {
        return TextSearchIntent(target);
      }
      // "bottle word" is odd — still prefer text of bottle spelling
      if (target.isNotEmpty) return TextSearchIntent(target);
    }

    // "the written word X" already handled; "written word X"
    if (q.startsWith('written word ') || q.startsWith('written text ')) {
      final rest = _cleanTextTarget(
        q.replaceFirst(RegExp(r'^written\s+(?:word|text)\s+'), ''),
      );
      if (rest.isEmpty) return const ClarifyIntent('Which word?');
      return TextSearchIntent(rest);
    }

    String? resolveObject(String phrase) {
      // Do not article-expand pure text-cue tokens into "a word"→bottle.
      if (_textCueWords.contains(phrase.trim())) return null;
      return SupportedObjects.resolve(phrase) ??
          SupportedObjects.resolve('a $phrase') ??
          SupportedObjects.resolve('an $phrase') ??
          SupportedObjects.resolve('the $phrase');
    }

    final early = resolveObject(q);
    if (early != null) {
      return ObjectSearchIntent(early);
    }

    q = _stripArticles(q);
    q = _stripTrailingTextHints(q);
    if (q.isEmpty) return const ClarifyIntent('Find what?');

    if (_isBareTextCue(q)) {
      return const ClarifyIntent('Which word?');
    }
    if (_startsWithAny(q, _textCueWords.toList())) {
      final rest = _cleanTextTarget(
        q.replaceFirst(
          RegExp(
            '^(?:${_textCueWords.map(RegExp.escape).join('|')})\\s+',
          ),
          '',
        ),
      );
      if (rest.isEmpty) return const ClarifyIntent('Which word?');
      return TextSearchIntent(rest);
    }

    final resolved = resolveObject(q);
    if (resolved != null) {
      return ObjectSearchIntent(resolved);
    }

    // Unknown noun → OCR text hunt (exhibitor, exhibition, summit, …).
    return TextSearchIntent(_cleanTextTarget(q));
  }

  bool _isBareTextCue(String q) {
    final t = q.trim();
    return _textCueWords.contains(t) ||
        RegExp(
          '^(?:a|an|the)\\s+(?:${_textCueWords.map(RegExp.escape).join('|')})\$',
        ).hasMatch(t);
  }

  String _stripTrailingTextHints(String q) {
    var t = q.trim();
    for (final hint in _trailingTextHints) {
      if (t.endsWith(hint)) {
        t = t.substring(0, t.length - hint.length).trim();
      }
    }
    return t;
  }

  String _cleanTextTarget(String q) {
    var t = _stripTrailingTextHints(q.trim());
    t = t.replaceFirst(RegExp(r'\s+is\s+written$'), '');
    t = t.replaceFirst(RegExp(r'^(?:the\s+)?(?:word|text|label|heading)\s+'), '');
    t = _stripArticles(t);
    // Drop leading "called" / "named"
    t = t.replaceFirst(RegExp(r'^(?:called|named)\s+'), '');
    // "exhibition word" leftover
    t = t.replaceFirst(
      RegExp(
        '\\s+(?:${_textCueWords.map(RegExp.escape).join('|')})\$',
      ),
      '',
    );
    return t.trim();
  }

  /// ASR often says "exhibition word" or "word exhibition" — normalize order.
  String _normalizeTextCues(String text) {
    var t = text;
    // "find exhibition word" → "find the word exhibition"
    // Do NOT rewrite bare "find a word" / "find the word".
    t = t.replaceAllMapped(
      RegExp(
        r'\b(find|look for|search for|locate)\s+([a-z0-9][a-z0-9\s]{0,40}?)\s+word\b',
      ),
      (m) {
        final verb = m.group(1)!;
        final target = m.group(2)!.trim();
        if (target.isEmpty ||
            _textCueWords.contains(target) ||
            RegExp(r'^(a|an|the)$').hasMatch(target)) {
          return m.group(0)!;
        }
        return '$verb the word $target';
      },
    );
    // "word for me, exhibition" (comma / for-me forms only — not "the word X")
    t = t.replaceAllMapped(
      RegExp(
        r'\b(?:this\s+)?word\s+for\s+me[, ]+([a-z0-9][a-z0-9\-]*)\b',
      ),
      (m) => 'the word ${m.group(1)}',
    );
    t = t.replaceAllMapped(
      RegExp(r'\bword,\s*([a-z0-9][a-z0-9\-]*)\b'),
      (m) => 'the word ${m.group(1)}',
    );
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalize(String raw) {
    return raw
        .toLowerCase()
        .replaceAll("'", '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripFillers(String text) {
    var t = text;
    for (var i = 0; i < 8; i++) {
      final next = t
          .replaceFirst(
            RegExp(
              r'^(hello|hi|hey|okay|ok|please|excuse me|thanks|thank you)[, ]+',
            ),
            '',
          )
          .replaceFirst(
            RegExp(
              r'^(can you|could you|would you|will you|can u)\s+',
            ),
            '',
          )
          .replaceFirst(
            RegExp(
              r'^(i want you to|i need you to|i would like you to|i would really like you to)\s+',
            ),
            '',
          )
          .replaceFirst(
            RegExp(
              r'^(i want to|i need to|help me|i wanna|please help me)\s+',
            ),
            '',
          )
          .replaceFirst(RegExp(r'\s+for me$'), '')
          .replaceFirst(RegExp(r'\s+please$'), '')
          .replaceFirst(RegExp(r'\s+thanks$'), '')
          .trim();
      if (next == t) break;
      t = next;
    }
    return t;
  }

  String _stripArticles(String q) {
    return q
        .replaceFirst(RegExp(r'^(a|an|the|my|this|that)\s+'), '')
        .replaceFirst(RegExp(r'^(a|an|the|my|this|that)\s+'), '')
        .replaceFirst(RegExp(r'\s+(is|are|was|were)$'), '')
        .trim();
  }

  bool _matchesAny(String text, List<String> phrases) {
    for (final p in phrases) {
      if (text == p || fuzzyEquals(text, p, threshold: 0.88)) return true;
    }
    return false;
  }

  bool _equalsAny(String text, List<String> phrases) {
    for (final p in phrases) {
      if (text == p) return true;
    }
    return false;
  }

  bool _containsExact(String text, List<String> phrases) {
    for (final p in phrases) {
      if (text.contains(p)) return true;
    }
    return false;
  }

  bool _containsAny(String text, List<String> phrases) {
    for (final p in phrases) {
      if (text.contains(p)) return true;
      if (bestFuzzyScore(p, text) >= 0.9) return true;
    }
    return false;
  }

  bool _startsWithAny(String text, List<String> prefixes) {
    for (final p in prefixes) {
      if (text == p || text.startsWith('$p ')) return true;
    }
    return false;
  }

  String? _extractAfter(String text, List<String> prefixes) {
    final sorted = [...prefixes]..sort((a, b) => b.length.compareTo(a.length));
    for (final p in sorted) {
      if (text == p) return '';
      // Require a word boundary after the prefix so "look a" does not
      // steal "look around" / "look ahead".
      if (text.startsWith('$p ')) {
        return text.substring(p.length + 1).trim();
      }
      final idx = text.indexOf(' $p ');
      if (idx >= 0) {
        return text.substring(idx + p.length + 2).trim();
      }
      if (text.endsWith(' $p')) return '';
    }
    return null;
  }

  bool _looksConversational(String text) {
    const starters = [
      'why',
      'how',
      'who',
      'when',
      'please tell',
      'explain',
      'tell me about',
      'what do you think',
      'help me understand',
    ];
    for (final s in starters) {
      if (text.startsWith(s)) return true;
    }
    final words = text.split(' ');
    return words.length >= 10;
  }

  HybridFindIntent? _hybridFind(String q) {
    final n = q.toLowerCase().trim();
    if (n == 'stop sign' ||
        n == 'a stop sign' ||
        n == 'the stop sign' ||
        n == 'stop signs') {
      return const HybridFindIntent(
        objectQuery: 'stop sign',
        textQuery: 'stop',
      );
    }
    return null;
  }
}

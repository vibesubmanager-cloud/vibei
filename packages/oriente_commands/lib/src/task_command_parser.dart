import 'package:oriente_domain/oriente_domain.dart';

/// Restricted vocabulary while an executing page is active (ignores noise/ticks).
class TaskCommandParser {
  const TaskCommandParser();

  static const vocabulary = <String>[
    'stop speaking',
    'be quiet',
    'mute',
    'stop looking',
    'stop',
    'cancel',
    'go back',
    'repeat',
    'keep looking',
    'what else',
    'what else can you see',
    'describe',
    'describe what you see',
    'look around',
    'what is in front of me',
    'what is around me',
    'what is that',
    'pause',
    'resume',
    'next paragraph',
    'previous paragraph',
    'torch',
  ];

  /// Non-intent read controls (handled by AppController → DocumentReadScreen).
  String? parseReadControl(String raw) {
    final text = raw
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_is(text, const ['pause'])) return 'pause';
    if (_is(text, const ['resume', 'continue reading'])) return 'resume';
    if (_is(text, const ['next paragraph', 'next'])) return 'next';
    if (_is(text, const ['previous paragraph', 'previous', 'back paragraph'])) {
      return 'previous';
    }
    if (_is(text, const ['torch', 'flashlight', 'light on', 'light off'])) {
      return 'torch';
    }
    return null;
  }

  AppIntent? parse(String raw) {
    final text = raw
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return null;

    if (_is(text, const ['stop speaking', 'be quiet', 'mute', 'quiet'])) {
      return const StopSpeakingIntent();
    }
    if (_is(text, const ['stop looking', 'stop search', 'stop searching'])) {
      return const StopLookingIntent();
    }
    if (_is(text, const ['stop', 'cancel', 'go back', 'back'])) {
      return const StopLookingIntent();
    }
    if (_is(text, const ['repeat', 'say again', 'again'])) {
      return const RepeatIntent();
    }
    if (_is(text, const [
      'keep looking',
      'continue',
      'keep searching',
      'what else',
      'what else can you see',
      'what else do you see',
      'what else is there',
      'tell me more',
    ])) {
      return const KeepLookingIntent();
    }
    if (_is(text, const [
      'describe',
      'describe this',
      'describe what you see',
      'look around',
      'look ahead',
      'what is in front of me',
      "what's in front of me",
      'what is around me',
      "what's around me",
      'what am i looking at',
      'what is that',
      "what's that",
      'tell me what you see',
      'what do you see',
    ])) {
      return const DescribeIntent(continuous: true);
    }
    return null; // ignore unmatched noise
  }

  bool _is(String text, List<String> phrases) {
    for (final p in phrases) {
      if (text == p || text.startsWith('$p ') || text.endsWith(' $p')) {
        return true;
      }
      if (text.contains(p) && text.length <= p.length + 8) return true;
    }
    return false;
  }
}

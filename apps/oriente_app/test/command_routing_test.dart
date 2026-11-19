import 'package:flutter_test/flutter_test.dart';
import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';

void main() {
  const parser = IntentParser();

  test('find a bottle → ObjectSearch', () {
    final i = parser.parse('find a bottle');
    expect(i, isA<ObjectSearchIntent>());
    expect((i as ObjectSearchIntent).query, 'bottle');
    expect(SupportedObjects.resolve('bottle'), 'bottle');
  });

  test('find a book → ObjectSearch', () {
    final i = parser.parse('find a book');
    expect(i, isA<ObjectSearchIntent>());
    expect(SupportedObjects.resolve('book'), 'book');
  });

  test('find a person → ObjectSearch', () {
    final i = parser.parse('find a person');
    expect(i, isA<ObjectSearchIntent>());
  });

  test('find my keys → text search when not a COCO object', () {
    final i = parser.parse('find my keys');
    expect(i, isA<TextSearchIntent>());
    expect((i as TextSearchIntent).query.toLowerCase(), contains('keys'));
  });

  test('find exhibit / exhibitions → text search', () {
    expect(parser.parse('find the exhibit'), isA<TextSearchIntent>());
    expect(parser.parse('can you find exhibitions'), isA<TextSearchIntent>());
    expect(
      (parser.parse('find exhibit') as TextSearchIntent).query.toLowerCase(),
      contains('exhibit'),
    );
  });

  test('find the text exhibitor → TextSearch', () {
    final i = parser.parse('find the text exhibitor');
    expect(i, isA<TextSearchIntent>());
    expect((i as TextSearchIntent).query.toLowerCase(), contains('exhibitor'));
  });

  test('find stop sign → hybrid or text', () {
    final i = parser.parse('find stop sign');
    expect(
      i is HybridFindIntent || i is TextSearchIntent || i is ObjectSearchIntent,
      isTrue,
    );
  });

  test('read nearby text → NearbyText', () {
    expect(parser.parse('read nearby text'), isA<NearbyTextIntent>());
  });

  test('describe my surroundings → Describe', () {
    expect(parser.parse('describe my surroundings'), isA<DescribeIntent>());
  });

  test('read this page → DocumentRead', () {
    expect(parser.parse('read this page'), isA<DocumentReadIntent>());
  });

  test('what is that → SCENE_DESCRIPTION (Describe)', () {
    expect(parser.parse('what is that'), isA<DescribeIntent>());
  });

  test('stop speaking → StopSpeaking', () {
    expect(parser.parse('stop speaking'), isA<StopSpeakingIntent>());
  });

  test('stop → Stop', () {
    expect(parser.parse('stop'), isA<StopIntent>());
  });

  test('repeat → Repeat', () {
    expect(parser.parse('repeat'), isA<RepeatIntent>());
  });

  test('unknown phrase → Clarify or Unsupported', () {
    final i = parser.parse('purple elephant dancing');
    expect(i is ClarifyIntent || i is UnsupportedIntent, isTrue);
  });

  test('found announcement uses asked label', () {
    final s = mergeFoundGuidance(queryLabel: 'bottle', moveCloser: true);
    expect(s.toLowerCase(), contains('bottle'));
    expect(s.toLowerCase(), contains('closer'));
  });
}

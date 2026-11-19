import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = IntentParser();
  const task = TaskCommandParser();

  test('find the bottle', () {
    final i = parser.parse('find the bottle');
    expect(i, isA<ObjectSearchIntent>());
    expect((i as ObjectSearchIntent).query, 'bottle');
  });

  test('hello can you look a bottle for me', () {
    final i = parser.parse('hello can you look a bottle for me');
    expect(i, isA<ObjectSearchIntent>());
  });

  test('describe phrases', () {
    expect(parser.parse('describe what you see'), isA<DescribeIntent>());
    expect(parser.parse('what is around me'), isA<DescribeIntent>());
  });

  test('task stop speaking vs stop looking', () {
    expect(task.parse('stop speaking'), isA<StopSpeakingIntent>());
    expect(task.parse('be quiet'), isA<StopSpeakingIntent>());
    expect(task.parse('stop looking'), isA<StopLookingIntent>());
    expect(task.parse('stop'), isA<StopLookingIntent>());
    expect(task.parse('go back'), isA<StopLookingIntent>());
    expect(task.parse('repeat'), isA<RepeatIntent>());
    expect(task.parse('keep looking'), isA<KeepLookingIntent>());
    expect(task.parse('random noise ticks'), isNull);
  });

  test('search text bag', () {
    final i = parser.parse('search text bag');
    expect(i, isA<TextSearchIntent>());
    expect((i as TextSearchIntent).query, 'bag');
  });

  test('nearby text and nearby objects', () {
    expect(parser.parse('nearby text'), isA<NearbyTextIntent>());
    expect(parser.parse('nearby objects'), isA<DescribeIntent>());
  });

  test('find stop sign → hybrid', () {
    final i = parser.parse('find stop sign');
    expect(i, isA<HybridFindIntent>());
    final h = i as HybridFindIntent;
    expect(h.objectQuery, 'stop sign');
    expect(h.textQuery, 'stop');
  });

  test('find aspirin → text when not a detector class', () {
    expect(parser.parse('find aspirin'), isA<TextSearchIntent>());
  });

  test('describe routing offline vs detail', () {
    expect(parser.parse('what is in front of me'), isA<DescribeIntent>());
    expect(parser.parse('describe my surroundings'), isA<DescribeIntent>());
    expect(
      (parser.parse('describe my surroundings') as DescribeIntent).continuous,
      isTrue,
    );
    expect(parser.parse('describe in detail'), isA<DescribeIntent>());
    expect(parser.parse('read it to me'), isA<DocumentReadIntent>());
  });
}

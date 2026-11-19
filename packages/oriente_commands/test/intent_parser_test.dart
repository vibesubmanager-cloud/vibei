import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = IntentParser();

  test('find a bottle → object search', () {
    final intent = parser.parse('find a bottle');
    expect(intent, isA<ObjectSearchIntent>());
    expect((intent as ObjectSearchIntent).query, 'bottle');
  });

  test('find my keys → text when not a COCO class', () {
    expect(parser.parse('find my keys'), isA<TextSearchIntent>());
  });

  test('find the word aspirin → text search', () {
    final intent = parser.parse('find the word aspirin');
    expect(intent, isA<TextSearchIntent>());
    expect((intent as TextSearchIntent).query, 'aspirin');
  });

  test('what is that → SCENE_DESCRIPTION', () {
    expect(parser.parse("what's that"), isA<DescribeIntent>());
  });

  test('what is around me → describe', () {
    expect(parser.parse('what is around me'), isA<DescribeIntent>());
  });


  test('stop → stop', () {
    expect(parser.parse('stop'), isA<StopIntent>());
  });

  test('fuzzy asprin similarity', () {
    expect(similarity('asprin', 'aspirin'), greaterThan(0.8));
  });
}

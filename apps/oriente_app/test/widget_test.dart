import 'package:flutter_test/flutter_test.dart';
import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';

void main() {
  test('command router maps find my keys', () {
    const parser = IntentParser();
    final intent = parser.parse('find my keys');
    expect(intent, isA<ObjectSearchIntent>());
    expect((intent as ObjectSearchIntent).query, 'keys');
  });
}

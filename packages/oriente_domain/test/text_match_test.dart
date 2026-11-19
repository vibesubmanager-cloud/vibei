import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  const m = TextMatcher();

  test('case and punctuation', () {
    expect(m.matches('STOP', 'Stop!!!'), isTrue);
    expect(m.matches('exit', 'EXIT.'), isTrue);
  });

  test('fuzzy misread', () {
    expect(m.matches('aspirin', 'asprin'), isTrue);
  });

  test('partial and multi-line phrase', () {
    final hits = m.matchAll('open hours', ['Open', 'Hours 9-5', 'Closed']);
    expect(hits, isNotEmpty);
  });
}

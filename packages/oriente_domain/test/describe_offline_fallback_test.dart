import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  final d = SceneDescriber(minHits: 1);

  test('offline describe groups table items, not a raw list', () {
    final text = d.summarize(const [
      SceneObject(
        id: 't',
        label: 'dining table',
        cx: 0.5,
        cy: 0.6,
        width: 0.55,
        height: 0.35,
        score: 0.9,
        hits: 3,
      ),
      SceneObject(
        id: 'tv',
        label: 'tv',
        cx: 0.4,
        cy: 0.4,
        width: 0.25,
        height: 0.2,
        score: 0.9,
        hits: 3,
      ),
      SceneObject(
        id: 'k',
        label: 'keyboard',
        cx: 0.45,
        cy: 0.55,
        width: 0.22,
        height: 0.08,
        score: 0.9,
        hits: 3,
      ),
      SceneObject(
        id: 'm',
        label: 'mouse',
        cx: 0.6,
        cy: 0.55,
        width: 0.08,
        height: 0.06,
        score: 0.85,
        hits: 3,
      ),
    ]).toLowerCase();
    expect(text.contains('placed on it') || text.contains('computer setup'), isTrue);
    expect(text.contains('tv.') && text.contains('keyboard.') && text.contains('mouse.'), isFalse);
  });

  test('empty → clear message', () {
    expect(
      d.summarize(const []),
      'I do not see clear objects ahead.',
    );
  });
}
